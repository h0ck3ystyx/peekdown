import SwiftUI

struct ContentView: View {
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
                    Text("Quick Look for Markdown files")
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
                Text("Select any .md or .markdown file in Finder and press Space to see it rendered as a formatted document.")
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
                Toggle("Experimental Mermaid diagrams", isOn: $preferences.diagrams)
                Toggle("Experimental display equations", isOn: $preferences.equations)
                Text("Settings apply when you reopen Quick Look. Diagrams support small flowcharts and sequence diagrams; unsupported content remains source text.")
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Show experiment demo in Finder") {
                    if let url = Bundle.main.url(forResource: "Experimental-preview", withExtension: "md") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                Button("Reset preview settings") { preferences = .defaults }
            }

            Divider()

            Text("Markdown · tables · task lists · code blocks · autolinks · footnotes · alerts")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .onChange(of: preferences) { value in value.save() }
        .padding(28)
        .frame(width: 480)
    }
}
