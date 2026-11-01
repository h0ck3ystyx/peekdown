import SwiftUI

struct ContentView: View {
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
                Label("Troubleshooting", systemImage: "wrench.and.screwdriver")
                    .font(.headline)
                Text("If previews don't appear, reset the Quick Look daemon in Terminal:")
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("qlmanage -r && qlmanage -r cache && killall Finder")
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
            }

            Divider()

            Text("Markdown · tables · task lists · code blocks · YAML · autolinks · footnotes · alerts")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(28)
        .frame(width: 480)
    }
}
