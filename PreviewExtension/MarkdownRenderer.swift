import AppKit

/// Renders Markdown to an NSAttributedString using only AppKit — no WebKit,
/// no JavaScript, no HTML importer. Rendering stays inside the extension sandbox.
enum MarkdownRenderer {
    static func attributedString(from source: String, fontSize: CGFloat = 14) -> NSAttributedString {
        RenderingSession().attributedString(from: source, fontSize: fontSize)
    }
}

// Reference state belongs to one document, including recursive inline/block rendering.
// Never share mutable footnote numbering between simultaneous Quick Look requests.
private final class RenderingSession {
    private var highlightBudget = SyntaxHighlighter.maxDocumentLength
    private var definitions: [String: [String]] = [:]
    private var referenceOrder: [String] = []
    private var referenceNumbers: [String: Int] = [:]

    // MARK: - Public entry point

    func attributedString(from source: String, fontSize: CGFloat = 14) -> NSAttributedString {
        let normalized = MarkdownText.stripFrontMatter(source)
        let lines = extractDefinitions(normalized.components(separatedBy: "\n"))
        let out = NSMutableAttributedString(attributedString: renderBlocks(lines, fontSize: fontSize))
        if !referenceOrder.isEmpty {
            out.append(heading(2, text: "Footnotes", fontSize: fontSize))
            var index = 0
            // Rendering a note can discover another note. Each defined ID is queued once,
            // so self-references and cycles cannot produce an unbounded expansion.
            while index < referenceOrder.count {
                let id = referenceOrder[index]
                let body = renderBlocks(definitions[id] ?? [], fontSize: fontSize)
                out.append(NSAttributedString(string: "\(index + 1). ", attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                    .foregroundColor: NSColor.labelColor
                ]))
                out.append(body)
                if !body.string.hasSuffix("\n") { out.append(NSAttributedString(string: "\n")) }
                index += 1
            }
        }
        return out
    }

    private func renderBlocks(_ lines: [String], fontSize: CGFloat, depth: Int = 0) -> NSAttributedString {
        guard depth < 32 else { return paragraph(lines.joined(separator: "\n"), fontSize: fontSize) }
        let out = NSMutableAttributedString()
        var i = 0

        while i < lines.count {
            let raw = lines[i]
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { i += 1; continue }

            // Only up to three leading spaces are allowed on non-code blocks.
            if raw.hasPrefix("    ") || raw.hasPrefix("\t") {
                var code: [String] = []
                while i < lines.count {
                    let line = lines[i]
                    if line.hasPrefix("    ") { code.append(String(line.dropFirst(4))) }
                    else if line.hasPrefix("\t") { code.append(String(line.dropFirst())) }
                    else if line.isEmpty, i + 1 < lines.count,
                            lines[i + 1].hasPrefix("    ") || lines[i + 1].hasPrefix("\t") { code.append("") }
                    else { break }
                    i += 1
                }
                out.append(codeBlock(code.joined(separator: "\n"), fontSize: fontSize))
                continue
            }

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
                let hint = String(t.dropFirst(fence.count))
                var code: [String] = []
                i += 1
                while i < lines.count && !isClosingFence(lines[i], marker: fence) {
                    code.append(lines[i]); i += 1
                }
                i += 1 // skip closing fence
                out.append(codeBlock(code.joined(separator: "\n"), fontSize: fontSize, hint: hint))
                continue
            }

            // Horizontal rule
            if isHorizontalRule(t) {
                out.append(horizontalRule(fontSize: fontSize))
                i += 1; continue
            }

            // Blockquotes and GitHub alerts. An unquoted blank ends the block.
            if quoteContent(raw) != nil {
                var quote: [String] = []
                while i < lines.count, let content = quoteContent(lines[i]) {
                    quote.append(content)
                    i += 1
                }
                out.append(blockquote(quote, fontSize: fontSize, depth: depth))
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
                if quoteContent(l) != nil { break }
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

    private func isAllowedScheme(_ url: String) -> Bool {
        // Trim whitespace and newlines
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Return false for empty strings or strings without a colon
        guard !trimmed.isEmpty, trimmed.contains(":") else {
            return false
        }
        
        // Extract scheme (everything before first colon, lowercased)
        guard let colonIndex = trimmed.firstIndex(of: ":") else {
            return false
        }
        let scheme = trimmed[..<colonIndex].lowercased()
        
        // Check allowed schemes
        switch scheme {
        case "http", "https":
            // For http/https, verify there's a // after the colon and something after that
            let afterColon = trimmed.index(after: colonIndex)
            guard afterColon < trimmed.endIndex else { return false }
            let rest = String(trimmed[afterColon...])
            // Must start with // and have more content
            return rest.hasPrefix("//") && rest.count > 2
        case "mailto":
            // For mailto, just need something after the colon
            let afterColon = trimmed.index(after: colonIndex)
            return afterColon < trimmed.endIndex
        default:
            return false
        }
    }

    // MARK: - Block-level matchers

    private func isClosingFence(_ line: String, marker: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let character = marker.first else { return false }
        let run = trimmed.prefix(while: { $0 == character })
        return run.count >= marker.count && trimmed.dropFirst(run.count).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func quoteContent(_ line: String) -> String? {
        let spaces = line.prefix(while: { $0 == " " }).count
        guard spaces <= 3 else { return nil }
        let trimmed = line.dropFirst(spaces)
        guard trimmed.first == ">" else { return nil }
        let rest = trimmed.dropFirst()
        return String(rest.first == " " ? rest.dropFirst() : rest)
    }

    private func footnoteDefinition(_ line: String) -> (id: String, text: String)? {
        let spaces = line.prefix(while: { $0 == " " }).count
        guard spaces <= 3 else { return nil }
        let text = line.dropFirst(spaces)
        guard text.hasPrefix("[^"), let end = text.range(of: "]:") else { return nil }
        let id = String(text[text.index(text.startIndex, offsetBy: 2)..<end.lowerBound])
        guard !id.isEmpty, !id.contains(where: { $0.isWhitespace || $0 == "[" || $0 == "]" }) else { return nil }
        return (id, String(text[end.upperBound...]).trimmingCharacters(in: .whitespaces))
    }

    private func extractDefinitions(_ lines: [String]) -> [String] {
        var body: [String] = []
        var fence: String?
        var listIndent: Int?
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if let marker = fence {
                body.append(line)
                if isClosingFence(line, marker: marker) { fence = nil }
                index += 1
                continue
            }
            // Indented list content is not a top-level definition, including
            // fences nested under a list marker. Leave it for the list renderer.
            if let indent = listIndent,
               line.trimmingCharacters(in: .whitespaces).isEmpty || leadingWhitespaceCount(line) > indent {
                body.append(line)
                index += 1
                continue
            }
            listIndent = isListMarker(line) ? leadingWhitespaceCount(line) : nil
            if !line.hasPrefix("    "), !line.hasPrefix("\t"), let marker = fenceMarker(line.trimmingCharacters(in: .whitespaces)) {
                fence = marker
                body.append(line)
                index += 1
                continue
            }
            guard let definition = footnoteDefinition(line) else {
                body.append(line)
                index += 1
                continue
            }
            var content = [definition.text]
            index += 1
            while index < lines.count {
                let next = lines[index]
                if next.hasPrefix("    ") { content.append(String(next.dropFirst(4))) }
                else if next.hasPrefix("\t") { content.append(String(next.dropFirst())) }
                else if next.trimmingCharacters(in: .whitespaces).isEmpty, index + 1 < lines.count,
                        lines[index + 1].hasPrefix("    ") || lines[index + 1].hasPrefix("\t") { content.append("") }
                else { break }
                index += 1
            }
            // First definition wins deterministically; unused definitions stay hidden.
            if definitions[definition.id] == nil { definitions[definition.id] = content }
            body.append("")
        }
        return body
    }

    private func atxHeading(_ line: String) -> (level: Int, text: String)? {
        guard let re = try? NSRegularExpression(pattern: "^(#{1,6})\\s+(.*)$") else { return nil }
        let ns = line as NSString
        guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let level = ns.substring(with: m.range(at: 1)).count
        var text = ns.substring(with: m.range(at: 2))
        text = text.replacingOccurrences(of: "\\s+#+\\s*$", with: "", options: .regularExpression)
        return (level, text.trimmingCharacters(in: .whitespaces))
    }

    private func isSetextUnderline(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.range(of: "^=+\\s*$", options: .regularExpression) != nil
            || t.range(of: "^-+\\s*$", options: .regularExpression) != nil
    }

    private func fenceMarker(_ line: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "^(`{3,}|~{3,})") else { return nil }
        let ns = line as NSString
        guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        return line.range(of: "^[ \\t]*([*_-][ \\t]*){3,}$", options: .regularExpression) != nil
    }

    private func isListMarker(_ line: String) -> Bool {
        return line.range(of: "^\\s*([-*+]|\\d+[.)])\\s+", options: .regularExpression) != nil
    }

    private func isTableSeparator(_ line: String) -> Bool {
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

    private func parseList(_ lines: [String], from start: Int) -> (ordered: Bool, items: [ListItem], next: Int) {
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
            if indent <= baseIndent,
               quoteContent(l) != nil || atxHeading(l) != nil || fenceMarker(l) != nil || isHorizontalRule(l) {
                break
            }
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

    private func parseTable(_ lines: [String], from start: Int) -> (header: [String], aligns: [String], rows: [[String]], next: Int) {
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

    private func splitTableRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func leadingWhitespaceCount(_ s: String) -> Int {
        var n = 0
        for c in s { if c == " " || c == "\t" { n += 1 } else { break } }
        return n
    }

    // MARK: - Block renderers

    private func heading(_ level: Int, text: String, fontSize: CGFloat) -> NSAttributedString {
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

    private func paragraph(_ text: String, fontSize: CGFloat) -> NSAttributedString {
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

    private func codeBlock(_ code: String, fontSize: CGFloat, hint: String = "") -> NSAttributedString {
        let ps = NSMutableParagraphStyle()
        ps.paragraphSpacing = 8
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: codeBackground,
            .paragraphStyle: ps
        ]
        let out = NSMutableAttributedString(string: code, attributes: attrs)
        let length = out.length
        if length <= SyntaxHighlighter.maxBlockLength, length <= highlightBudget,
           let language = SyntaxHighlighter.Language(hint: hint) {
            highlightBudget -= length
            SyntaxHighlighter.highlight(out, code: code, language: language)
        }
        out.append(NSAttributedString(string: "\n"))
        return out
    }

    private func blockquote(_ lines: [String], fontSize: CGFloat, depth: Int) -> NSAttributedString {
        let alerts: [String: (String, NSColor)] = [
            "[!NOTE]": ("ⓘ Note", .systemBlue),
            "[!TIP]": ("✓ Tip", .systemGreen),
            "[!IMPORTANT]": ("◆ Important", .systemPurple),
            "[!WARNING]": ("⚠ Warning", .systemOrange),
            "[!CAUTION]": ("⛔ Caution", .systemRed)
        ]
        let alert = alerts[lines.first?.trimmingCharacters(in: .whitespaces) ?? ""]
        let contents = alert == nil ? lines : Array(lines.dropFirst())
        let out = NSMutableAttributedString()
        if let (title, color) = alert {
            out.append(NSAttributedString(string: title + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: color,
                .paragraphStyle: spacingStyle(before: 4, after: 4)
            ]))
        }
        out.append(renderBlocks(contents, fontSize: fontSize, depth: depth + 1))
        // Preserve nested formatting, links, and code while adding quote indentation.
        out.enumerateAttributes(in: NSRange(location: 0, length: out.length)) { attrs, range, _ in
            let ps = (attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()
            ps.headIndent += 16
            ps.firstLineHeadIndent += 16
            ps.paragraphSpacing = max(ps.paragraphSpacing, 4)
            out.addAttribute(.paragraphStyle, value: ps, range: range)
            if let (_, color) = alert {
                out.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.08), range: range)
            } else if attrs[.foregroundColor] as? NSColor == NSColor.labelColor {
                out.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            }
        }
        return out
    }

    private func list(_ items: [ListItem], ordered: Bool, fontSize: CGFloat) -> NSAttributedString {
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

    private func table(_ header: [String], aligns: [String], rows: [[String]], fontSize: CGFloat) -> NSAttributedString {
        let mono = NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)
        let monoBold = NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .bold)
        func cell(_ text: String, bold: Bool) -> NSAttributedString {
            let rendered = NSMutableAttributedString(attributedString: renderInline(text, [
                .font: bold ? monoBold : mono, .foregroundColor: NSColor.labelColor
            ]))
            // Box-drawn columns require a uniform glyph advance. Keep references
            // as [n] in table cells instead of shrinking them into superscripts.
            rendered.enumerateAttributes(in: NSRange(location: 0, length: rendered.length)) { attrs, range, _ in
                let traits = (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
                var font = NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: traits.contains(.bold) ? .bold : .regular)
                if traits.contains(.italic) {
                    font = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: font.pointSize) ?? font
                }
                rendered.addAttribute(.font, value: font, range: range)
                rendered.removeAttribute(.superscript, range: range)
            }
            return rendered
        }
        // Render once, in document order, so footnotes in cells get stable numbers.
        let h = header.map { cell($0, bold: true) }
        let body = rows.map { row in header.indices.map { cell($0 < row.count ? row[$0] : "", bold: false) } }
        var widths = h.map { max(1, $0.string.count) }
        for row in body {
            for (index, value) in row.enumerated() { widths[index] = max(widths[index], value.string.count) }
        }
        let charWidth = ("M" as NSString).size(withAttributes: [.font: mono]).width
        let maxTotal = max(20, Int(620 / max(charWidth, 1)))
        var total = widths.reduce(0, +) + 3 * widths.count + 1
        while total > maxTotal {
            guard let index = widths.indices.max(by: { widths[$0] < widths[$1] }), widths[index] > 6 else { break }
            widths[index] -= 1
            total -= 1
        }
        func wrap(_ text: NSAttributedString, width: Int) -> [NSAttributedString] {
            let chars = Array(text.string)
            var offsets = [0]
            for c in chars { offsets.append(offsets.last! + String(c).utf16.count) }
            var result: [NSAttributedString] = []
            var start = 0
            while start < chars.count {
                var end = min(start + width, chars.count)
                if end < chars.count, let space = (start..<end).last(where: { chars[$0].isWhitespace }), space > start { end = space }
                let range = NSRange(location: offsets[start], length: offsets[end] - offsets[start])
                result.append(text.attributedSubstring(from: range))
                start = end
                while start < chars.count && chars[start].isWhitespace { start += 1 }
            }
            return result.isEmpty ? [NSAttributedString(string: "")] : result
        }
        let hwrapped = h.enumerated().map { wrap($1, width: widths[$0]) }
        let bwrapped = body.map { row in row.enumerated().map { wrap($1, width: widths[$0]) } }
        let out = NSMutableAttributedString()
        let borderAttrs: [NSAttributedString.Key: Any] = [.font: mono, .foregroundColor: NSColor.secondaryLabelColor]
        func border(_ left: String, _ middle: String, _ right: String) {
            out.append(NSAttributedString(string: left + widths.map { String(repeating: "─", count: $0 + 2) }.joined(separator: middle) + right + "\n", attributes: borderAttrs))
        }
        func appendRow(_ cells: [[NSAttributedString]]) {
            for line in 0..<(cells.map { $0.count }.max() ?? 1) {
                out.append(NSAttributedString(string: "│", attributes: borderAttrs))
                for index in widths.indices {
                    let value = line < cells[index].count ? cells[index][line] : NSAttributedString(string: "")
                    let padding = max(0, widths[index] - value.string.count)
                    let alignment = index < aligns.count ? aligns[index] : "left"
                    let left = alignment == "right" ? padding : (alignment == "center" ? padding / 2 : 0)
                    out.append(NSAttributedString(string: " " + String(repeating: " ", count: left), attributes: borderAttrs))
                    out.append(value)
                    out.append(NSAttributedString(string: String(repeating: " ", count: padding - left) + " │", attributes: borderAttrs))
                }
                out.append(NSAttributedString(string: "\n"))
            }
        }
        border("┌", "┬", "┐")
        appendRow(hwrapped)
        border("├", "┼", "┤")
        for row in bwrapped { appendRow(row) }
        border("└", "┴", "┘")
        out.append(NSAttributedString(string: "\n"))
        return out
    }

    private func horizontalRule(fontSize: CGFloat) -> NSAttributedString {
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

    private func spacingStyle(before: CGFloat, after: CGFloat) -> NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.paragraphSpacingBefore = before
        ps.paragraphSpacing = after
        return ps
    }

    // MARK: - Inline rendering

    private func renderInline(_ text: String, _ base: [NSAttributedString.Key: Any], depth: Int = 0) -> NSAttributedString {
        guard depth < 64 else { return NSAttributedString(string: text, attributes: base) }
        let result = NSMutableAttributedString()
        let chars = Array(text)
        // Avoid repeatedly scanning unmatched brackets in large malformed documents.
        var brackets: [Int: Int] = [:]
        var stack: [Int] = []
        var escaped = false
        for (index, character) in chars.enumerated() {
            if escaped { escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if character == "[" { stack.append(index) }
            if character == "]", let opening = stack.popLast() { brackets[opening] = index }
        }
        // Scan around @ once, with email-length bounds, instead of applying an
        // unanchored regex repeatedly to long malformed prose.
        var emails: [Int: (label: String, end: Int)] = [:]
        func asciiAlphanumeric(_ c: Character) -> Bool {
            c.unicodeScalars.count == 1 && c.unicodeScalars.first!.value < 128 && (c.isLetter || c.isNumber)
        }
        func localCharacter(_ c: Character) -> Bool {
            asciiAlphanumeric(c) || ".!#$%&'*+/=?^_`{|}~-".contains(c)
        }
        func domainCharacter(_ c: Character) -> Bool { asciiAlphanumeric(c) || c == "-" || c == "." }
        if base[.link] == nil, let expression = emailExpression {
            for at in chars.indices where chars[at] == "@" {
                var start = at
                while start > 0 && at - start < 64 && localCharacter(chars[start - 1]) { start -= 1 }
                if start > 0 && localCharacter(chars[start - 1]) { continue }
                var end = at + 1
                while end < chars.count && end - start < 254 && domainCharacter(chars[end]) { end += 1 }
                if end < chars.count && domainCharacter(chars[end]) { continue }
                while end > at + 1 && chars[end - 1] == "." { end -= 1 }
                let label = String(chars[start..<end])
                if expression.firstMatch(in: label, range: NSRange(location: 0, length: (label as NSString).length)) != nil {
                    emails[start] = (label, end)
                }
            }
        }
        var tickEnds: [Int: Int] = [:]
        var tickRuns: [(start: Int, count: Int)] = []
        var cursor = 0
        while cursor < chars.count {
            if chars[cursor] != "`" { cursor += 1; continue }
            let start = cursor
            while cursor < chars.count && chars[cursor] == "`" { cursor += 1 }
            tickEnds[start] = cursor
            tickRuns.append((start, cursor - start))
        }
        var nextTick: [Int: Int] = [:]
        var lastTick: [Int: Int] = [:]
        for run in tickRuns.reversed() {
            nextTick[run.start] = lastTick[run.count]
            lastTick[run.count] = run.start
        }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count,
               chars[i + 1].unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.union(.symbols).contains($0) }) {
                result.append(NSAttributedString(string: String(chars[i + 1]), attributes: base))
                i += 2; continue
            }

            // Code spans can use matching runs of backticks, protecting all new syntax.
            if c == "`" {
                let end = tickEnds[i] ?? i + 1
                if let closing = nextTick[i] {
                    let code = String(chars[end..<closing])
                    result.append(NSAttributedString(string: code, attributes: codeAttrs))
                    i = tickEnds[closing] ?? closing + 1; continue
                }
                result.append(NSAttributedString(string: String(chars[i..<end]), attributes: base))
                i = end; continue
            }

            if c == "!", i + 1 < chars.count, let parsed = parseLink(chars, start: i + 1, brackets: brackets) {
                let alt = parsed.label.isEmpty ? "[image]" : parsed.label
                result.append(NSAttributedString(string: alt, attributes: [
                    .font: (base[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 14),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]))
                i = parsed.end; continue
            }

            // Explicit labels keep their own destination, even if the label is a URL.
            if c == "[", let parsed = parseLink(chars, start: i, brackets: brackets) {
                var attrs = base
                if isAllowedScheme(parsed.url) {
                    attrs[.foregroundColor] = NSColor.systemBlue
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    attrs[.link] = parsed.url
                }
                result.append(renderInline(parsed.label, attrs, depth: depth + 1))
                i = parsed.end; continue
            }

            if base[.link] == nil, c == "[", i + 1 < chars.count, chars[i + 1] == "^", let end = brackets[i] {
                let id = String(chars[(i + 2)..<end])
                if definitions[id] != nil {
                    let number: Int
                    if let existing = referenceNumbers[id] { number = existing }
                    else {
                        number = referenceOrder.count + 1
                        referenceNumbers[id] = number
                        referenceOrder.append(id)
                    }
                    var attrs = base
                    let size = (base[.font] as? NSFont)?.pointSize ?? 14
                    attrs[.font] = NSFont.systemFont(ofSize: max(9, size * 0.8))
                    attrs[.superscript] = 1
                    result.append(NSAttributedString(string: "[\(number)]", attributes: attrs))
                } else {
                    result.append(NSAttributedString(string: String(chars[i...end]), attributes: base))
                }
                i = end + 1; continue
            }

            let canOpen = i + 1 < chars.count && !chars[i + 1].isWhitespace
                && !(c == "_" && i > 0 && (chars[i - 1].isLetter || chars[i - 1].isNumber))
            if canOpen, (c == "*" || c == "_"), i + 1 < chars.count, chars[i + 1] == c,
               let close = findClosing(chars, marker: String(repeating: String(c), count: 2), from: i + 2) {
                result.append(renderInline(String(chars[(i + 2)..<close]), applyBold(base), depth: depth + 1))
                i = close + 2; continue
            }
            if canOpen, c == "*" || c == "_", let close = findClosing(chars, marker: String(c), from: i + 1) {
                result.append(renderInline(String(chars[(i + 1)..<close]), applyItalic(base), depth: depth + 1))
                i = close + 1; continue
            }
            if c == "~", i + 1 < chars.count, chars[i + 1] == "~",
               let close = findClosing(chars, marker: "~~", from: i + 2) {
                var attrs = base
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                result.append(renderInline(String(chars[(i + 2)..<close]), attrs, depth: depth + 1))
                i = close + 2; continue
            }
            if base[.link] == nil, let link = autolink(chars, from: i, emails: emails) {
                var attrs = base
                attrs[.foregroundColor] = NSColor.systemBlue
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attrs[.link] = link.url
                result.append(NSAttributedString(string: link.label, attributes: attrs))
                i = link.end; continue
            }

            result.append(NSAttributedString(string: String(c), attributes: base))
            i += 1
        }
        return result
    }

    private func parseLink(_ chars: [Character], start: Int, brackets: [Int: Int]) -> (label: String, url: String, end: Int)? {
        guard let closing = brackets[start], closing + 1 < chars.count, chars[closing + 1] == "(" else { return nil }
        var end = closing + 2
        var balance = 1
        var escaped = false
        while end < chars.count {
            let c = chars[end]
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "(" { balance += 1 }
            else if c == ")" {
                balance -= 1
                if balance == 0 { break }
            }
            end += 1
        }
        guard end < chars.count else { return nil }
        let contents = String(chars[(closing + 2)..<end]).trimmingCharacters(in: .whitespaces)
        let destination: String
        if contents.hasPrefix("<"), let angle = contents.firstIndex(of: ">") {
            destination = String(contents[contents.index(after: contents.startIndex)..<angle])
        } else { destination = contents.components(separatedBy: .whitespaces).first ?? "" }
        return (String(chars[(start + 1)..<closing]), destination, end + 1)
    }

    private let emailExpression = try? NSRegularExpression(
        pattern: #"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$"#)

    private func autolink(_ chars: [Character], from start: Int, emails: [Int: (label: String, end: Int)]) -> (label: String, url: String, end: Int)? {
        let angle = chars[start] == "<"
        guard angle || start == 0 || chars[start - 1].isWhitespace || "(*_~".contains(chars[start - 1]) else { return nil }
        let begin = angle ? start + 1 : start
        guard begin < chars.count else { return nil }
        // Inspect a short prefix before scanning a token; most prose is not a URL.
        let prefix = String(chars[begin..<min(chars.count, begin + 8)]).lowercased()
        let web = prefix.hasPrefix("http://") || prefix.hasPrefix("https://") || (!angle && prefix.hasPrefix("www."))
        if !web {
            guard let email = emails[begin] else { return nil }
            if angle {
                guard email.end < chars.count, chars[email.end] == ">" else { return nil }
            }
            return (email.label, "mailto:" + email.label, angle ? email.end + 1 : email.end)
        }
        var end = begin
        while end < chars.count && !chars[end].isWhitespace && chars[end] != "<" && chars[end] != ">" && chars[end] != "`" {
            if !angle && (chars[end] == "\"" || chars[end] == "'") { break }
            if !angle && chars[end] == "[", end + 1 < chars.count, chars[end + 1] == "^" { break }
            end += 1
        }
        if angle {
            guard end < chars.count, chars[end] == ">", end > begin else { return nil }
        } else {
            // Leave sentence punctuation and unmatched closing brackets outside the link.
            var balance: [Character: Int] = [")": 0, "]": 0, "}": 0]
            for c in chars[begin..<end] {
                if let closing = [Character("("): Character(")"), "[": "]", "{": "}"][c] { balance[closing, default: 0] += 1 }
                else if balance[c] != nil { balance[c, default: 0] -= 1 }
            }
            while end > begin {
                let last = chars[end - 1]
                if ".,:;!?".contains(last) { end -= 1 }
                else if let count = balance[last], count < 0 { balance[last] = count + 1; end -= 1 }
                else { break }
            }
        }
        guard end > begin else { return nil }
        let label = String(chars[begin..<end])
        let destination = prefix.hasPrefix("www.") ? "http://" + label : label
        guard let url = URL(string: destination), let host = url.host, !host.isEmpty,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              !host.contains("@"), (!prefix.hasPrefix("www.") || host.dropFirst(4).contains(".")) else { return nil }
        return (label, destination, angle ? end + 1 : end)
    }

    private func findClosing(_ chars: [Character], marker: String, from: Int) -> Int? {
        let m = Array(marker)
        var i = from
        while i + m.count <= chars.count {
            if chars[i] == "\\" { i += 2; continue }
            if marker.first == "_", i + m.count < chars.count,
               chars[i + m.count].isLetter || chars[i + m.count].isNumber { i += 1; continue }
            var match = true
            for (o, ch) in m.enumerated() where chars[i + o] != ch { match = false; break }
            if match { return i }
            i += 1
        }
        return nil
    }

    // MARK: - Attribute helpers

    private func applyBold(_ attrs: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var a = attrs
        let f = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 14)
        a[.font] = NSFont(descriptor: f.fontDescriptor.withSymbolicTraits(.bold), size: f.pointSize) ?? f
        return a
    }

    private func applyItalic(_ attrs: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var a = attrs
        let f = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 14)
        a[.font] = NSFont(descriptor: f.fontDescriptor.withSymbolicTraits(.italic), size: f.pointSize) ?? f
        return a
    }

    private lazy var codeAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
        .foregroundColor: NSColor.labelColor,
        .backgroundColor: codeBackground
    ]

    private let codeBackground: NSColor = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? NSColor(calibratedWhite: 0.20, alpha: 1) : NSColor(calibratedWhite: 0.93, alpha: 1)
    }
}
