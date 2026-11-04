import SwiftUI

struct ContentView: View {
    @ObservedObject var updates: UpdateChecker
    @State private var demoError: String?
    @State private var preferences = PreviewSettings.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Peekdown")
                        .font(.largeTitle.bold())
                    Text("Quick Look for Markdown and YAML files")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            Group {
                Label("Installation", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                Text("Keep this app installed. macOS registers the Quick Look and thumbnail extensions automatically when the app is present.")
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Group {
                Label("Usage", systemImage: "hand.tap")
                    .font(.headline)
                Text("Select a Markdown or YAML file in Finder and press Space. Markdown opens as a formatted document. YAML opens in a syntax-colored code panel, or as plain text when the file is too large or not valid YAML.")
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Group {
                Text("Preview appearance").font(.headline)
                HStack {
                    Text("Text size")
                    Slider(value: $preferences.textScale, in: 0.8...1.6, step: 0.1)
                    Text("\(Int(preferences.textScale * 100))%").monospacedDigit().frame(width: 48)
                }
                Toggle("Compact paragraph spacing", isOn: $preferences.compact)
                HStack {
                    Text("Code line spacing")
                    Slider(value: $preferences.codeLineSpacing, in: 0...6, step: 1)
                }
                Toggle("Show front-matter metadata", isOn: $preferences.metadata)
                Toggle("Experimental Mermaid diagrams", isOn: $preferences.diagrams)
                Toggle("Experimental display equations", isOn: $preferences.equations)
                Text("Settings apply when you reopen Quick Look. Diagrams support small flowcharts and sequence diagrams; unsupported content remains source text.")
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Save experiment demo…") { saveDemo() }
                Button("Reset preview settings") { preferences = .defaults }
            }

            Divider()

            Button("Check for Updates…") { updates.check() }
            Text("Markdown · tables · task lists · code blocks · YAML · autolinks · footnotes · alerts")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .alert("Couldn’t save the demo", isPresented: Binding(get: { demoError != nil }, set: { if !$0 { demoError = nil } })) {
            Button("OK") { demoError = nil }
        } message: { Text(demoError ?? "") }
        .onChange(of: preferences) { value in value.save() }
        .padding(28)
        .frame(width: 480)
    }
    private func saveDemo() {
        let panel = NSSavePanel()
        panel.title = "Save the Peekdown experiment demo"
        panel.nameFieldStringValue = "Peekdown-demo.md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            guard let source = Bundle.main.url(forResource: "Experimental-preview", withExtension: "md") else {
                throw NSError(domain: "Peekdown", code: 1, userInfo: [NSLocalizedDescriptionKey: "The demo is missing from this app. Please reinstall Peekdown."])
            }
            try Data(contentsOf: source).write(to: destination, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch { demoError = error.localizedDescription }
    }

}
