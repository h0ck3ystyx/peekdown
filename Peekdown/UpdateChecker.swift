import SwiftUI

@MainActor
final class UpdateChecker: ObservableObject {
    enum State { case checking, current, newerInstalled, available(AvailableRelease), failed(String) }
    @Published private(set) var state: State = .checking
    let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    private var service: UpdateService?
    private var window: NSWindow?

    func check() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Peekdown Updates"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: UpdateStatusView(checker: self))
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        guard service == nil else { return }
        guard let local = ReleaseVersion(installed) else {
            state = .failed("The installed app version could not be read. Please download a current release from GitHub.")
            return
        }
        state = .checking
        let service = UpdateService { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.service = nil
                switch result {
                case .success(let release):
                    if local < release.version { self.state = .available(release) }
                    else { self.state = local == release.version ? .current : .newerInstalled }
                case .failure(let error):
                    let message: String
                    if let failure = error as? UpdateFailure { message = failure.localizedDescription }
                    else if (error as NSError).code == NSURLErrorNotConnectedToInternet { message = "You appear to be offline. Connect to the internet and try again." }
                    else if (error as NSError).code == NSURLErrorTimedOut { message = "The update check timed out. Please try again." }
                    else { message = "Couldn’t connect to GitHub. Please check your connection and try again." }
                    self.state = .failed(message)
                }
            }
        }
        self.service = service
        service.start()
    }
}

private struct UpdateStatusView: View {
    @ObservedObject var checker: UpdateChecker
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Peekdown Updates").font(.title2.bold())
            Text("Installed version: \(checker.installed)").foregroundColor(.secondary)
            switch checker.state {
            case .checking:
                ProgressView("Checking GitHub for a stable release…")
            case .current:
                Text("You’re up to date.")
                Button("Check Again") { checker.check() }
            case .newerInstalled:
                Text("You’re running a newer version than the latest stable release.")
                Button("Check Again") { checker.check() }
            case .failed(let message):
                Text(message).fixedSize(horizontal: false, vertical: true)
                Button("Try Again") { checker.check() }
            case .available(let release):
                Text("Peekdown \(release.tag) is available.").font(.headline)
                ScrollView { Text(verbatim: release.notes).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                Button("View Release on GitHub…") { NSWorkspace.shared.open(release.pageURL) }
            }
            Spacer(minLength: 0)
            Text("Checks run only when requested. Downloads and installation are manual.")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(24).frame(width: 480, height: 380)
    }
}
