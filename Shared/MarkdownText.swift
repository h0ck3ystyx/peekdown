import Foundation

enum MarkdownText {
    static func stripFrontMatter(_ source: String) -> String {
        let text = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---",
              let closing = lines.dropFirst().firstIndex(where: { $0 == "---" || $0 == "..." }) else {
            return text
        }
        return lines.dropFirst(closing + 1).joined(separator: "\n")
    }
}
