import SwiftUI

@main
struct PeekdownApp: App {
    @StateObject private var updates = UpdateChecker()

    var body: some Scene {
        WindowGroup {
            ContentView(updates: updates)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updates.check() }
            }
        }
    }
}
