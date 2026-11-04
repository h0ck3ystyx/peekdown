import Foundation

enum MarkdownText {
    static func frontMatter(_ source: String) -> (metadata: String?, body: String) {
        let text = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---",
              let closing = lines.dropFirst().firstIndex(where: { $0 == "---" || $0 == "..." }) else {
            return (nil, text)
        }
        return (lines[1..<closing].joined(separator: "\n"), lines.dropFirst(closing + 1).joined(separator: "\n"))
    }
    static func stripFrontMatter(_ source: String) -> String { frontMatter(source).body }
}
