import Foundation

/// Conservative source-preserving MDX view, not a JSX/JavaScript parser.
/// Blocks containing MDX-looking syntax are shown literally, never stripped.
enum StaticMDX {
    static func markdownView(of source: String) -> String {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var output = ["# Static MDX preview", "", "Components, imports, and expressions are shown as source, never executed. Surrounding Markdown is best-effort.", ""]
        var paragraph: [String] = []
        var fence: (Character, Int)?
        func flush() {
            guard !paragraph.isEmpty else { return }
            let body = paragraph.joined(separator: "\n")
            let unsupported = paragraph.contains {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return t.hasPrefix("import ") || t.hasPrefix("export ") || t.contains("<") || t.contains("{") || t.contains("}")
            }
            if unsupported {
                // Find a fence longer than any sequence in the original source.
                var longest = 0, run = 0
                for c in body { run = c == "`" ? run+1 : 0; longest = max(longest, run) }
                let marker = String(repeating: "`", count: max(3, longest+1))
                output += [marker+"tsx", body, marker]
            } else { output += paragraph }
            paragraph.removeAll()
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let active = fence {
                output.append(line)
                let count = trimmed.prefix(while: { $0 == active.0 }).count
                if count >= active.1 && trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
            } else if let first = trimmed.first, first == "`" || first == "~",
                      trimmed.prefix(while: { $0 == first }).count >= 3 {
                flush()
                fence = (first, trimmed.prefix(while: { $0 == first }).count)
                output.append(line)
            } else if trimmed.isEmpty {
                flush(); output.append("")
            } else { paragraph.append(line) }
        }
        flush()
        return output.joined(separator: "\n")
    }
}
