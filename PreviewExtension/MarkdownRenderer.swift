import AppKit

/// Renders Markdown to an NSAttributedString using only AppKit — no WebKit,
/// no JavaScript, no HTML importer. Rendering stays inside the extension sandbox.
enum MarkdownRenderer {

    // MARK: - Public entry point

    static func attributedString(from source: String, fontSize: CGFloat = 14) -> NSAttributedString {
        let normalized = MarkdownText.stripFrontMatter(source)
        let lines = normalized.components(separatedBy: "\n")
        let out = NSMutableAttributedString()
        var i = 0

        while i < lines.count {
            let raw = lines[i]
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { i += 1; continue }

            // ATX heading
            if let h = atxHeading(t) {
                out.append(heading(h.level, text: h.text, fontSize: fontSize))
                i += 1; continue
            }

            // Setext heading
            if i + 1 < lines.count, isSetextUnderline(lines[i + 1]) {
                let level = lines[i + 1].trimmingCharacters(in: .whitespaces).hasPrefix("=") ? 1 : 2
                out.append(heading(level, text: t, fontSize: fontSize))
                i += 2; continue
            }

            // Fenced code block
            if let fence = fenceMarker(t) {
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix(fence) {
                    code.append(lines[i]); i += 1
                }
                i += 1 // skip closing fence
                out.append(codeBlock(code.joined(separator: "\n"), fontSize: fontSize))
                continue
            }

            // Horizontal rule
            if isHorizontalRule(t) {
                out.append(horizontalRule(fontSize: fontSize))
                i += 1; continue
            }

            // Blockquote
            if t.hasPrefix(">") {
                var quote: [String] = []
                while i < lines.count {
                    let l = lines[i]
                    if l.hasPrefix(">") {
                        let rest = l.hasPrefix("> ") ? String(l.dropFirst(2)) : String(l.dropFirst(1))
                        quote.append(rest)
                        i += 1
                    } else if l.trimmingCharacters(in: .whitespaces).isEmpty,
                              i + 1 < lines.count, lines[i + 1].hasPrefix(">") {
                        quote.append("")
                        i += 1
                    } else { break }
                }
                out.append(blockquote(quote, fontSize: fontSize))
                continue
            }

            // List
            if isListMarker(t) {
                let parsed = parseList(lines, from: i)
                out.append(list(parsed.items, ordered: parsed.ordered, fontSize: fontSize))
                i = parsed.next
                continue
            }

            // Table
            if t.contains("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                let parsed = parseTable(lines, from: i)
                out.append(table(parsed.header, aligns: parsed.aligns, rows: parsed.rows, fontSize: fontSize))
                i = parsed.next
                continue
            }

            // Paragraph
            var para: [String] = []
            while i < lines.count {
                let l = lines[i]
                let lt = l.trimmingCharacters(in: .whitespaces)
                if lt.isEmpty { break }
                if atxHeading(lt) != nil { break }
                if fenceMarker(lt) != nil { break }
                if isListMarker(l) { break }
                if lt.hasPrefix(">") { break }
                if isHorizontalRule(lt) { break }
                if i + 1 < lines.count, isSetextUnderline(lines[i + 1]) { break }
                if l.contains("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) { break }
                para.append(l); i += 1
            }
            if !para.isEmpty {
                out.append(paragraph(para.joined(separator: " "), fontSize: fontSize))
            }
        }

        return out
    }

    // MARK: - Link scheme validation

    private static func isAllowedScheme(_ url: String) -> Bool {
        // Trim whitespace and newlines, strip control characters
        let cleaned = url
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0 >= " " && $0 != "\u{7F}" }
        
        // Return false for empty strings
        guard !cleaned.isEmpty else { return false }
        
        // Parse with URL to extract scheme
        guard let parsedURL = URL(string: cleaned),
              let scheme = parsedURL.scheme?.lowercased() else {
            // No valid scheme found, treat as plain text
            return false
        }
        
        // Check allowed schemes
        switch scheme {
        case "http", "https":
            // For http/https, require a non-empty host
            return parsedURL.host?.isEmpty == false
        case "mailto":
            return true
        default:
            return false
        }
    }

    // MARK: - Block-level matchers

    private static func atxHeading(_ line: String) -> (level: Int, text: String)? {
        guard let re = try? NSRegularExpression(pattern: "^(#{1,6})\\s+(.*)$") else { return nil }
        let ns = line as NSString
        guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let level = ns.substring(with: m.range(at: 1)).count
        var text = ns.substring(with: m.range(at: 2))
        text = text.replacingOccurrences(of: "\\s+#+\\s*$", with: "", options: .regularExpression)
        return (level, text.trimmingCharacters(in: .whitespaces))
    }

    private static func isSetextUnderline(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.range(of: "^=+\\s*$", options: .regularExpression) != nil
            || t.range(of: "^-+\\s*$", options: .regularExpression) != nil
    }

    private static func fenceMarker(_ line: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "^(`{3,}|~{3,})") else { return nil }
        let ns = line as NSString
        guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        return line.range(of: "^[ \\t]*([*_-][ \\t]*){3,}$", options: .regularExpression) != nil
    }

    private static func isListMarker(_ line: String) -> Bool {
        return line.range(of: "^\\s*([-*+]|\\d+[.)])\\s+", options: .regularExpression) != nil
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        // Guard against catastrophic backtracking: limit line length for regex matching
        guard t.count < 10_000 else { return false }
        return t.range(of: "^\\|?\\s*:?-+:?\\s*(\\|\\s*:?-+:?\\s*)+\\|?\\s*$", options: .regularExpression) != nil
    }

    // MARK: - Block parsers

    private struct ListItem {
        var lines: [String]
        var indent: Int
    }

    private static func parseList(_ lines: [String], from start: Int) -> (ordered: Bool, items: [ListItem], next: Int) {
        let first = lines[start]
        let ordered = first.range(of: "^\\s*\\d+[.)]", options: .regularExpression) != nil
        let markerPattern = ordered ? "^\\s*\\d+[.)]\\s+" : "^\\s*[-*+]\\s+"
        let otherMarkerPattern = ordered ? "^\\s*[-*+]\\s+" : "^\\s*\\d+[.)]\\s+"
        let baseIndent = leadingWhitespaceCount(first)

        var items: [ListItem] = []
        var i = start
        while i < lines.count {
            let l = lines[i]
            if l.trimmingCharacters(in: .whitespaces).isEmpty {
                // blank line inside list: keep going only if the next line is a
                // same-type list marker at (or beyond) the list's base indent.
                if i + 1 < lines.count,
                   lines[i + 1].range(of: markerPattern, options: .regularExpression) != nil,
                   leadingWhitespaceCount(lines[i + 1]) >= baseIndent {
                    i += 1; continue
                }
                break
            }
            let indent = leadingWhitespaceCount(l)
            if indent < baseIndent { break }
            // A different list type (ordered vs unordered) starts a new list.
            if l.range(of: otherMarkerPattern, options: .regularExpression) != nil { break }
            if l.range(of: markerPattern, options: .regularExpression) != nil {
                let content = l.replacingOccurrences(of: markerPattern, with: "", options: .regularExpression)
                items.append(ListItem(lines: [content], indent: indent))
                i += 1
            } else {
                // continuation line of the previous item
                if !items.isEmpty { items[items.count - 1].lines.append(l.trimmingCharacters(in: .whitespaces)) }
                i += 1
            }
        }
        return (ordered, items, i)
    }

    private static func parseTable(_ lines: [String], from start: Int) -> (header: [String], aligns: [String], rows: [[String]], next: Int) {
        let header = splitTableRow(lines[start])
        let aligns = splitTableRow(lines[start + 1]).map { cell -> String in
            if cell.hasPrefix(":") && cell.hasSuffix(":") { return "center" }
            if cell.hasSuffix(":") { return "right" }
            if cell.hasPrefix(":") { return "left" }
            return "left"
        }
        var rows: [[String]] = []
        var i = start + 2
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.isEmpty || !t.contains("|") { break }
            rows.append(splitTableRow(t))
            i += 1
        }
        return (header, aligns, rows, i)
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func leadingWhitespaceCount(_ s: String) -> Int {
        var n = 0
        for c in s { if c == " " || c == "\t" { n += 1 } else { break } }
        return n
    }

    // MARK: - Block renderers

    private static func heading(_ level: Int, text: String, fontSize: CGFloat) -> NSAttributedString {
        let sizes: [CGFloat] = [0, 30, 24, 19, 16, 14, 12]
        let size = level <= 6 ? sizes[level] : fontSize
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: .bold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: spacingStyle(before: 12, after: 4)
        ]
        let out = NSMutableAttributedString()
        out.append(renderInline(text, attrs))
        out.append(NSAttributedString(string: "\n"))
        return out
    }

    private static func paragraph(_ text: String, fontSize: CGFloat) -> NSAttributedString {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: spacingStyle(before: 0, after: 8)
        ]
        let out = NSMutableAttributedString()
        out.append(renderInline(text, attrs))
        out.append(NSAttributedString(string: "\n"))
        return out
    }

    private static func codeBlock(_ code: String, fontSize: CGFloat) -> NSAttributedString {
        let ps = NSMutableParagraphStyle()
        ps.paragraphSpacing = 8
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: codeBackground,
            .paragraphStyle: ps
        ]
        let out = NSMutableAttributedString(string: code, attributes: attrs)
        out.append(NSAttributedString(string: "\n"))
        return out
    }

    private static func blockquote(_ lines: [String], fontSize: CGFloat) -> NSAttributedString {
        let ps = NSMutableParagraphStyle()
        ps.headIndent = 16
        ps.firstLineHeadIndent = 16
        ps.paragraphSpacing = 8
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: ps
        ]
        let out = NSMutableAttributedString()
        out.append(renderInline(lines.joined(separator: " "), attrs))
        out.append(NSAttributedString(string: "\n"))
        return out
    }

    private static func list(_ items: [ListItem], ordered: Bool, fontSize: CGFloat) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let baseIndent = items.first?.indent ?? 0
        for (n, item) in items.enumerated() {
            var text = item.lines.joined(separator: " ")
            let indentLevel = max(0, (item.indent - baseIndent) / 2)

            // Task-list checkbox
            var marker: String
            if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
                marker = "☑  "
                text.removeFirst(4)
            } else if text.hasPrefix("[ ] ") {
                marker = "☐  "
                text.removeFirst(4)
            } else {
                marker = ordered ? "\(n + 1). " : "• "
            }

            let ps = NSMutableParagraphStyle()
            let step = fontSize * 1.4
            ps.headIndent = fontSize * 1.6 + CGFloat(indentLevel) * step
            ps.firstLineHeadIndent = fontSize * 0.4 + CGFloat(indentLevel) * step
            ps.paragraphSpacing = 3
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: ps
            ]
            let itemStr = NSMutableAttributedString(string: marker, attributes: attrs)
            itemStr.append(renderInline(text, attrs))
            itemStr.append(NSAttributedString(string: "\n"))
            out.append(itemStr)
        }
        out.append(NSAttributedString(string: "\n"))
        return out
    }

    private static func table(_ header: [String], aligns: [String], rows: [[String]], fontSize: CGFloat) -> NSAttributedString {
        // Strip unambiguous inline markers so cells read as plain text.
        func plain(_ s: String) -> String {
            s.replacingOccurrences(of: "`", with: "")
             .replacingOccurrences(of: "**", with: "")
        }
        let h = header.map(plain)
        let body = rows.map { $0.map(plain) }

        // Natural column widths.
        var widths = h.map { $0.count }
        for row in body {
            for (c, cell) in row.enumerated() where c < widths.count {
                widths[c] = max(widths[c], cell.count)
            }
        }
        // Cap the total width so the table fits the ~730px preview panel.
        // Measure the real monospace advance rather than guessing; a border line
        // that exceeds the container hard-wraps into stray fragments.
        let measureFont = NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)
        let charW = ("M" as NSString).size(withAttributes: [.font: measureFont]).width
        let maxTotal = max(20, Int(620 / max(charW, 1)))
        func totalWidth(_ w: [Int]) -> Int { w.reduce(0, +) + 3 * w.count + 1 }
        var total = totalWidth(widths)
        while total > maxTotal {
            guard let idx = widths.indices.max(by: { widths[$0] < widths[$1] }), widths[idx] > 6 else { break }
            widths[idx] -= 1
            total -= 1
        }

        func wrap(_ text: String, _ w: Int) -> [String] {
            if text.count <= w { return [text] }
            var lines: [String] = []
            var cur = ""
            for word in text.split(separator: " ") {
                let ws = String(word)
                if cur.isEmpty { cur = ws }
                else if cur.count + 1 + ws.count <= w { cur += " " + ws }
                else { lines.append(cur); cur = ws }
            }
            if !cur.isEmpty { lines.append(cur) }
            var out: [String] = []
            for l in lines {
                var s = l
                while s.count > w { out.append(String(s.prefix(w))); s = String(s.dropFirst(w)) }
                out.append(s)
            }
            return out.isEmpty ? [""] : out
        }

        func pad(_ cell: String, _ w: Int, _ align: String) -> String {
            let diff = max(0, w - cell.count)
            switch align {
            case "right": return String(repeating: " ", count: diff) + cell
            case "center":
                let left = diff / 2
                return String(repeating: " ", count: left) + cell + String(repeating: " ", count: diff - left)
            default: return cell + String(repeating: " ", count: diff)
            }
        }

        func border(_ left: String, _ mid: String, _ right: String) -> String {
            let segs = widths.map { String(repeating: "─", count: $0 + 2) }
            return left + segs.joined(separator: mid) + right
        }

        let hwrapped = h.enumerated().map { wrap($1, widths[$0]) }
        let bwrapped = body.map { row in row.enumerated().map { wrap($1, widths[$0]) } }
        let headerLineCount = hwrapped.map { $0.count }.max() ?? 1

        let mono = NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)
        let monoBold = NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .bold)
        let borderColor = NSColor.secondaryLabelColor
        let out = NSMutableAttributedString()

        func appendCells(_ cells: [String], bold: Bool) {
            var parts: [String] = []
            for (c, cell) in cells.enumerated() where c < widths.count {
                parts.append(" " + pad(cell, widths[c], c < aligns.count ? aligns[c] : "left") + " ")
            }
            out.append(NSAttributedString(string: "│" + parts.joined(separator: "│") + "│\n",
                                          attributes: [.font: bold ? monoBold : mono,
                                                       .foregroundColor: NSColor.labelColor]))
        }

        out.append(NSAttributedString(string: border("┌", "┬", "┐") + "\n", attributes: [.font: mono, .foregroundColor: borderColor]))
        for li in 0..<headerLineCount {
            appendCells(hwrapped.map { li < $0.count ? $0[li] : "" }, bold: true)
        }
        out.append(NSAttributedString(string: border("├", "┼", "┤") + "\n", attributes: [.font: mono, .foregroundColor: borderColor]))
        for row in bwrapped {
            let lc = row.map { $0.count }.max() ?? 1
            for li in 0..<lc {
                appendCells(row.map { li < $0.count ? $0[li] : "" }, bold: false)
            }
        }
        out.append(NSAttributedString(string: border("└", "┴", "┘") + "\n", attributes: [.font: mono, .foregroundColor: borderColor]))
        out.append(NSAttributedString(string: "\n"))
        return out
    }

    private static func horizontalRule(fontSize: CGFloat) -> NSAttributedString {
        let out = NSMutableAttributedString(
            string: String(repeating: "—", count: 42),
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.separatorColor,
                .paragraphStyle: spacingStyle(before: 8, after: 8)
            ]
        )
        out.append(NSAttributedString(string: "\n"))
        return out
    }

    private static func spacingStyle(before: CGFloat, after: CGFloat) -> NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.paragraphSpacingBefore = before
        ps.paragraphSpacing = after
        return ps
    }

    // MARK: - Inline rendering

    private static func renderInline(_ text: String, _ base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let chars = Array(text)
        var i = 0

        while i < chars.count {
            let c = chars[i]

            // Inline code
            if c == "`" {
                var j = i + 1
                while j < chars.count && chars[j] != "`" { j += 1 }
                if j < chars.count {
                    let code = String(chars[(i + 1)..<j])
                    result.append(NSAttributedString(string: code, attributes: codeAttrs))
                    i = j + 1; continue
                }
            }

            // Image ![alt](url)
            if c == "!" && i + 1 < chars.count && chars[i + 1] == "[",
               let parsed = parseLink(String(chars[i...]), start: 1) {
                let alt = parsed.label.isEmpty ? "[image]" : parsed.label
                result.append(NSAttributedString(string: alt, attributes: [
                    .font: (base[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 14),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]))
                i += parsed.end; continue
            }

            // Link [text](url)
            if c == "[", let parsed = parseLink(String(chars[i...]), start: 0) {
                var linkAttrs = base
                // Only make it clickable if the scheme is allowed
                if !parsed.url.isEmpty && isAllowedScheme(parsed.url) {
                    linkAttrs[.foregroundColor] = NSColor.systemBlue
                    linkAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    linkAttrs[.link] = parsed.url
                }
                result.append(renderInline(parsed.label, linkAttrs))
                i += parsed.end; continue
            }

            // Bold ** or __
            if (c == "*" || c == "_"), i + 1 < chars.count, chars[i + 1] == c {
                let marker = String(c) + String(c)
                if let close = findClosing(chars, marker: marker, from: i + 2) {
                    let inner = String(chars[(i + 2)..<close])
                    result.append(renderInline(inner, applyBold(base)))
                    i = close + 2; continue
                }
            }

            // Italic * or _
            if c == "*" || c == "_" {
                if let close = findClosing(chars, marker: String(c), from: i + 1) {
                    let inner = String(chars[(i + 1)..<close])
                    result.append(renderInline(inner, applyItalic(base)))
                    i = close + 1; continue
                }
            }

            // Strikethrough ~~
            if c == "~", i + 1 < chars.count, chars[i + 1] == "~" {
                if let close = findClosing(chars, marker: "~~", from: i + 2) {
                    let inner = String(chars[(i + 2)..<close])
                    var strike = base
                    strike[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                    result.append(renderInline(inner, strike))
                    i = close + 2; continue
                }
            }

            // Plain character
            result.append(NSAttributedString(string: String(c), attributes: base))
            i += 1
        }

        return result
    }

    private static func parseLink(_ text: String, start: Int) -> (label: String, url: String, end: Int)? {
        let chars = Array(text)
        guard start < chars.count, chars[start] == "[" else { return nil }
        var j = start + 1
        var depth = 1
        while j < chars.count && depth > 0 {
            if chars[j] == "[" { depth += 1 }
            if chars[j] == "]" { depth -= 1 }
            if depth > 0 { j += 1 }
        }
        guard j < chars.count else { return nil }
        let label = String(chars[(start + 1)..<j])
        let k = j + 1
        guard k < chars.count, chars[k] == "(" else { return nil }
        var m = k + 1
        while m < chars.count && chars[m] != ")" { m += 1 }
        guard m < chars.count else { return nil }
        let url = String(chars[(k + 1)..<m]).components(separatedBy: " ").first ?? ""
        return (label, url, m + 1)
    }

    private static func findClosing(_ chars: [Character], marker: String, from: Int) -> Int? {
        let m = Array(marker)
        var i = from
        while i + m.count <= chars.count {
            var match = true
            for (o, ch) in m.enumerated() where chars[i + o] != ch { match = false; break }
            if match { return i }
            i += 1
        }
        return nil
    }

    // MARK: - Attribute helpers

    private static func applyBold(_ attrs: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var a = attrs
        let f = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 14)
        a[.font] = NSFont(descriptor: f.fontDescriptor.withSymbolicTraits(.bold), size: f.pointSize) ?? f
        return a
    }

    private static func applyItalic(_ attrs: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var a = attrs
        let f = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 14)
        a[.font] = NSFont(descriptor: f.fontDescriptor.withSymbolicTraits(.italic), size: f.pointSize) ?? f
        return a
    }

    private static let codeAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
        .foregroundColor: NSColor.labelColor,
        .backgroundColor: codeBackground
    ]

    private static let codeBackground: NSColor = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? NSColor(calibratedWhite: 0.20, alpha: 1) : NSColor(calibratedWhite: 0.93, alpha: 1)
    }
}
