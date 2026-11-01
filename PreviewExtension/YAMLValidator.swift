import Foundation

/// Structural check used before syntax-coloring a standalone YAML file.
/// A rejection keeps the preview readable as plain text. Tags are not resolved
/// and nothing in the document is executed.
enum YAMLValidator {
    /// Nil when `source` is structurally acceptable.
    static func rejectionReason(for source: String) -> String? {
        var parser = Parser(source)
        return parser.parse() ? nil : (parser.reason ?? "Invalid YAML")
    }

    static func isValid(_ source: String) -> Bool {
        rejectionReason(for: source) == nil
    }

    private struct Parser {
        var chars: [Character]
        var i = 0
        var line = 1
        var column = 0
        var reason: String?
        var depth = 0
        var anchors = Set<String>()

        init(_ source: String) {
            var text = source.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            if text.first == "\u{FEFF}" { text.removeFirst() }
            chars = Array(text)
        }

        private struct Mark { var i: Int; var line: Int; var column: Int }

        mutating func parse() -> Bool {
            if chars.contains("\0") { return fail("null byte") }
            guard skipStructure() else { return false }
            var needsDocumentStart = false
            while i < chars.count {
                if isAtMarker("---") {
                    guard consumeMarkerToken("---") else { return false }
                    anchors.removeAll()
                    needsDocumentStart = false
                    guard parseAfterDocumentStart() else { return false }
                    continue
                }
                if isAtMarker("...") { return fail("document end without a document") }
                if column == 0 && peek() == "%" {
                    guard parseDirective() else { return false }
                    needsDocumentStart = true
                    guard skipStructure() else { return false }
                    continue
                }
                if needsDocumentStart { return fail("directive requires a document start") }
                guard parseNode(parentIndent: -1) else { return false }
                guard column == 0 || i >= chars.count else { return fail("unfinished node") }
                anchors.removeAll()
                guard skipStructure() else { return false }
                if isAtMarker("...") {
                    guard consumeMarkerToken("...") else { return false }
                    guard finishLine() else { return false }
                    guard skipStructure() else { return false }
                    if i < chars.count && !isAtMarker("---") && peek() != "%" {
                        return fail("expected a document start after the document end")
                    }
                    continue
                }
                if i < chars.count && !isAtMarker("---") { return fail("extra document content") }
            }
            if needsDocumentStart { return fail("directive requires a document start") }
            return true
        }

        /// Content on the `---` line may be a plain value or a flow collection.
        /// A block sequence or block mapping on that same line is rejected.
        private mutating func parseAfterDocumentStart() -> Bool {
            guard skipSameLineSpaces() else { return false }
            if isAtLineEnd() {
                guard finishLine() else { return false }
                guard skipStructure() else { return false }
                if i >= chars.count || isAtMarker("---") { return true }
                if isAtMarker("...") {
                    guard consumeMarkerToken("...") else { return false }
                    guard finishLine() else { return false }
                    return skipStructure()
                }
                guard parseNode(parentIndent: -1) else { return false }
                return closeDocumentTail()
            }
            if peek() == "[" || peek() == "{" || peek() == "\"" || peek() == "'"
                || peek() == "|" || peek() == ">" || peek() == "*" || peek() == "&" || peek() == "!" {
                guard parseNode(parentIndent: column - 1) else { return false }
                return closeDocumentTail()
            }
            if peek() == "-" && isBoundary(1) { return fail("sequence is not allowed on a document start line") }
            if lineHasPlainKey() { return fail("mapping is not allowed on a document start line") }
            guard parseNode(parentIndent: column - 1) else { return false }
            return closeDocumentTail()
        }

        private mutating func closeDocumentTail() -> Bool {
            guard column == 0 || i >= chars.count else { return fail("unfinished document") }
            anchors.removeAll()
            guard skipStructure() else { return false }
            if isAtMarker("...") {
                guard consumeMarkerToken("...") else { return false }
                guard finishLine() else { return false }
                return skipStructure()
            }
            if i < chars.count && !isAtMarker("---") && !(column == 0 && peek() == "%") {
                return fail("extra document content")
            }
            return true
        }

        // MARK: Nodes

        private mutating func parseNode(parentIndent: Int) -> Bool {
            guard depth < 128 else { return fail("nesting limit") }
            depth += 1
            defer { depth -= 1 }
            guard column > parentIndent else { return fail("indentation") }
            let indent = column
            let startedInline = hasPriorContentOnLine()
            guard consumeProperties() else { return false }
            if isAtLineEnd() {
                guard finishLine() else { return false }
                let mark = here()
                guard skipStructure() else { return false }
                let floor = startedInline ? parentIndent : indent
                if i >= chars.count || column <= floor || isAtMarker("---") || isAtMarker("...") {
                    restore(mark)
                    return true
                }
                return parseNode(parentIndent: floor)
            }
            if peek() == "*" {
                guard consumeAlias() else { return false }
                return finishLine()
            }
            if peek() == "|" || peek() == ">" {
                let startsLine = !hasPriorContentOnLine()
                return parseBlockScalar(parentIndent: parentIndent, indicatorColumn: column, atLineStart: startsLine)
            }
            if peek() == "[" || peek() == "{" {
                guard parseFlow() else { return false }
                return finishLine()
            }
            if peek() == "-" && isBoundary(1) {
                return parseSequence(indent: indent)
            }
            if peek() == "?" && isBoundary(1) {
                return parseExplicitMapping(indent: indent)
            }
            if peek() == "\"" || peek() == "'" {
                let quoteLine = line
                guard parseQuoted() else { return false }
                guard skipSameLineSpaces() else { return false }
                if peek() == ":" && isValueColon(0) {
                    if line != quoteLine { return fail("multiline quoted key") }
                    return parseMappingValueAndSiblings(indent: indent)
                }
                return finishLine()
            }
            if lineHasPlainKey() {
                // `key: nested: value` is not a nested block mapping. A mapping may
                // still start after a sequence marker (`- key: value`).
                if previousSignificantOnLine() == ":" { return fail("mapping value is not allowed here") }
                return parseMapping(indent: indent)
            }
            let contentInline = hasPriorContentOnLine()
            let floor = contentInline ? parentIndent + 1 : column
            return parsePlainScalar(floor: floor)
        }

        private mutating func parseMapping(indent: Int) -> Bool {
            guard parsePlainKey() else { return false }
            return parseMappingValueAndSiblings(indent: indent)
        }

        private mutating func parseMappingValueAndSiblings(indent: Int) -> Bool {
            guard parseValue(indent: indent) else { return false }
            while true {
                let mark = here()
                guard skipStructure() else { return false }
                if i >= chars.count || isAtMarker("---") || isAtMarker("...") {
                    restore(mark)
                    return true
                }
                if column == indent && (lineHasPlainKey() || peek() == "\"" || peek() == "'") {
                    if peek() == "\"" || peek() == "'" {
                        let quoteLine = line
                        guard parseQuoted() else { return false }
                        if line != quoteLine { return fail("multiline quoted key") }
                        guard skipSameLineSpaces() else { return false }
                        guard peek() == ":" && isValueColon(0) else { return fail("expected a mapping key") }
                    } else {
                        guard parsePlainKey() else { return false }
                    }
                    guard parseValue(indent: indent) else { return false }
                    continue
                }
                if column > indent { return fail("unexpected indented content in a mapping") }
                restore(mark)
                return true
            }
        }

        private mutating func parsePlainKey() -> Bool {
            var any = false
            while let c = peek(), c != "\n" {
                if c == "\t" { return fail("tab in a plain key") }
                if c == "#" && isCommentStart() { return fail("comment in a key") }
                if c == ":" && isValueColon(0) { return any ? true : fail("empty key") }
                if c == " " {
                    var j = 0
                    while peek(j) == " " { j += 1 }
                    // Consume the entire run once; rescanning it at each space
                    // makes a long key quadratic in its input length.
                    while j > 0 { advance(); j -= 1 }
                    continue
                }
                if c != " " { any = true }
                advance()
            }
            return fail("expected a mapping key")
        }

        private mutating func parseValue(indent: Int) -> Bool {
            guard peek() == ":" && isValueColon(0) else { return fail("expected ':'") }
            advance()
            while peek() == " " { advance() }
            if peek() == "\t" { return fail("tab after ':'") }
            if isAtLineEnd() {
                guard finishLine() else { return false }
                let mark = here()
                guard skipStructure() else { return false }
                if i >= chars.count || column <= indent || isAtMarker("---") || isAtMarker("...") {
                    restore(mark)
                    return true
                }
                return parseNode(parentIndent: indent)
            }
            return parseNode(parentIndent: indent)
        }

        private mutating func parseSequence(indent: Int) -> Bool {
            while true {
                guard peek() == "-" && isBoundary(1) else { return fail("expected a sequence entry") }
                advance()
                if peek() == "\t" { return fail("tab in a sequence") }
                if peek() == " " { while peek() == " " { advance() } }
                if peek() == "\t" { return fail("tab in a sequence") }
                if isAtLineEnd() {
                    guard finishLine() else { return false }
                    let mark = here()
                    guard skipStructure() else { return false }
                    if i < chars.count && column > indent && !isAtMarker("---") && !isAtMarker("...") {
                        guard parseNode(parentIndent: indent) else { return false }
                    } else {
                        restore(mark)
                    }
                } else {
                    guard parseNode(parentIndent: indent) else { return false }
                }
                let mark = here()
                guard skipStructure() else { return false }
                if i < chars.count && column == indent && peek() == "-" && isBoundary(1) { continue }
                restore(mark)
                return true
            }
        }

        private mutating func parseExplicitMapping(indent: Int) -> Bool {
            while true {
                guard peek() == "?" && isBoundary(1) else { return fail("expected an explicit key") }
                advance()
                if peek() == "\t" { return fail("tab in an explicit key") }
                while peek() == " " { advance() }
                if isAtLineEnd() {
                    guard finishLine() else { return false }
                    let mark = here()
                    guard skipStructure() else { return false }
                    if i < chars.count && column > indent && !isAtMarker("---") && !isAtMarker("...") {
                        guard parseNode(parentIndent: indent) else { return false }
                    } else {
                        restore(mark)
                    }
                } else if peek() == "[" || peek() == "{" || peek() == "\"" || peek() == "'" {
                    guard parseNode(parentIndent: column - 1) else { return false }
                } else {
                    guard consumePlainLine(allowEmpty: false) else { return false }
                    guard finishLine() else { return false }
                }
                guard skipStructure() else { return false }
                guard column == indent, peek() == ":", isBoundary(1) else { return fail("expected an explicit value") }
                advance()
                while peek() == " " { advance() }
                if peek() == "\t" { return fail("tab after ':'") }
                if isAtLineEnd() {
                    guard finishLine() else { return false }
                    let nested = here()
                    guard skipStructure() else { return false }
                    if i < chars.count && column > indent && !isAtMarker("---") && !isAtMarker("...") {
                        guard parseNode(parentIndent: indent) else { return false }
                    } else {
                        restore(nested)
                    }
                } else {
                    guard parseNode(parentIndent: indent) else { return false }
                }
                let next = here()
                guard skipStructure() else { return false }
                if i < chars.count && column == indent && peek() == "?" && isBoundary(1) { continue }
                restore(next)
                return true
            }
        }

        private mutating func parsePlainScalar(floor: Int) -> Bool {
            guard consumePlainLine(allowEmpty: false) else { return false }
            guard finishLine() else { return false }
            while i < chars.count {
                let mark = here()
                while isBlankLine() { guard consumeEntireLine() else { return false } }
                if i >= chars.count { return true }
                if isCommentLine() || isAtMarker("---") || isAtMarker("...") {
                    restore(mark)
                    return true
                }
                guard let spaces = leadingSpaces() else { return fail("tab in a plain scalar") }
                if spaces < floor {
                    restore(mark)
                    return true
                }
                guard consumePlainLine(allowEmpty: false) else { return false }
                guard finishLine() else { return false }
            }
            return true
        }

        private mutating func parseBlockScalar(parentIndent: Int, indicatorColumn: Int, atLineStart: Bool) -> Bool {
            advance()
            var explicit: Int?
            func takeDigit() {
                if let value = peek()?.wholeNumberValue, (1...9).contains(value) {
                    explicit = value
                    advance()
                }
            }
            takeDigit()
            if peek() == "+" || peek() == "-" { advance() }
            if explicit == nil { takeDigit() }
            if peek()?.wholeNumberValue == 0 { return fail("block indent indicator cannot be 0") }
            guard finishLine() else { return false }
            let base = atLineStart ? indicatorColumn : parentIndent
            var detected = explicit.map { base + $0 }
            while i < chars.count {
                let mark = here()
                guard column == 0 else { return fail("block scalar position") }
                var spaces = 0
                while peek() == " " { advance(); spaces += 1 }
                if peek() == "\n" || peek() == nil {
                    if peek() == "\n" { advance() }
                    continue
                }
                if let contentIndent = detected {
                    if spaces < contentIndent {
                        restore(mark)
                        return true
                    }
                    while let c = peek(), c != "\n" { advance() }
                    if peek() == "\n" { advance() }
                } else if spaces <= base {
                    restore(mark)
                    return true
                } else {
                    detected = spaces
                    while let c = peek(), c != "\n" { advance() }
                    if peek() == "\n" { advance() }
                }
            }
            return true
        }

        // MARK: Flow and scalars

        private mutating func parseFlow() -> Bool {
            let closing: Character = peek() == "[" ? "]" : "}"
            advance()
            var needsComma = false
            while true {
                guard skipFlowSpace() else { return false }
                if peek() == closing {
                    advance()
                    return true
                }
                if i >= chars.count { return fail("unclosed flow collection") }
                if needsComma { return fail("missing comma in a flow collection") }
                if peek() == "," { return fail("empty flow entry") }
                guard parseFlowNode() else { return false }
                guard skipFlowSpace() else { return false }
                if isFlowColon() {
                    advance()
                    guard skipFlowSpace() else { return false }
                    if peek() != "," && peek() != closing && i < chars.count {
                        guard parseFlowNode() else { return false }
                        guard skipFlowSpace() else { return false }
                    }
                }
                if peek() == "," {
                    advance()
                    guard skipFlowSpace() else { return false }
                    if peek() == closing {
                        advance()
                        return true
                    }
                    if i >= chars.count { return fail("unclosed flow collection") }
                    needsComma = false
                    continue
                }
                needsComma = true
            }
        }

        private mutating func parseFlowNode() -> Bool {
            guard depth < 128 else { return fail("nesting limit") }
            depth += 1
            defer { depth -= 1 }
            while peek() == "&" || peek() == "!" {
                if peek() == "&" {
                    guard consumeAnchor() else { return false }
                } else {
                    guard consumeTag() else { return false }
                }
                guard skipFlowSpace() else { return false }
            }
            if peek() == "*" { return consumeAlias() }
            if peek() == "\"" || peek() == "'" { return parseQuoted() }
            if peek() == "[" || peek() == "{" { return parseFlow() }
            return parseFlowPlain()
        }

        private mutating func parseFlowPlain() -> Bool {
            let start = i
            while let c = peek() {
                if c == "\n" || c == "," || c == "[" || c == "]" || c == "{" || c == "}" || c == "#" { break }
                if c == "\t" { return fail("tab in a flow scalar") }
                if isFlowColon() { break }
                advance()
            }
            while i > start && chars[i - 1] == " " {
                i -= 1
                column -= 1
            }
            return i > start ? true : fail("empty flow entry")
        }

        private mutating func parseQuoted() -> Bool {
            let quote = peek()!
            advance()
            if quote == "'" {
                while i < chars.count {
                    if peek() == "'" {
                        advance()
                        if peek() == "'" { advance(); continue }
                        return true
                    }
                    advance()
                }
                return fail("unterminated single quote")
            }
            let simple: Set<Character> = ["0", "a", "b", "t", "n", "v", "f", "r", "e", " ", "\"", "/", "\\", "N", "_", "L", "P"]
            while i < chars.count {
                if peek() == "\\" {
                    advance()
                    guard let escaped = peek() else { return fail("unterminated escape") }
                    advance()
                    if escaped == "\n" { continue }
                    if escaped == "x" { guard consumeHex(2) else { return false }; continue }
                    if escaped == "u" { guard consumeHex(4) else { return false }; continue }
                    if escaped == "U" { guard consumeHex(8) else { return false }; continue }
                    if simple.contains(escaped) { continue }
                    return fail("unknown escape")
                }
                if peek() == "\"" { advance(); return true }
                advance()
            }
            return fail("unterminated double quote")
        }

        private mutating func consumePlainLine(allowEmpty: Bool) -> Bool {
            while peek() == " " { advance() }
            if peek() == "\t" { return fail("tab in a plain scalar") }
            var any = false
            while let c = peek(), c != "\n" {
                if c == "\t" { return fail("tab in a plain scalar") }
                if c == "#" && isCommentStart() { break }
                if c == ":" && isValueColon(0) { return fail("mapping value is not allowed in a plain scalar") }
                if c != " " { any = true }
                advance()
            }
            return any || allowEmpty ? true : fail("empty plain scalar")
        }

        // MARK: Properties

        private mutating func consumeProperties() -> Bool {
            var sawAnchor = false
            var sawTag = false
            while true {
                if peek() == "&" && !sawAnchor {
                    guard consumeAnchor() else { return false }
                    sawAnchor = true
                    guard skipSameLineSpaces() else { return false }
                } else if peek() == "!" && !sawTag {
                    guard consumeTag() else { return false }
                    sawTag = true
                    guard skipSameLineSpaces() else { return false }
                } else {
                    return true
                }
            }
        }

        private mutating func consumeAnchor() -> Bool {
            guard peek() == "&" else { return fail("expected an anchor") }
            advance()
            let name = readName()
            guard !name.isEmpty else { return fail("empty anchor") }
            guard anchors.insert(name).inserted else { return fail("duplicate anchor \(name)") }
            return true
        }

        private mutating func consumeAlias() -> Bool {
            guard peek() == "*" else { return fail("expected an alias") }
            advance()
            let name = readName()
            guard !name.isEmpty else { return fail("empty alias") }
            guard anchors.contains(name) else { return fail("undefined alias \(name)") }
            return true
        }

        private mutating func consumeTag() -> Bool {
            guard peek() == "!" else { return fail("expected a tag") }
            advance()
            if peek() == "<" {
                advance()
                while let c = peek(), c != ">", c != "\n" { advance() }
                guard peek() == ">" else { return fail("unterminated tag") }
                advance()
                return true
            }
            if peek() == "!" { advance() }
            while let c = peek(), isNameChar(c) { advance() }
            return true
        }

        private mutating func readName() -> String {
            let start = i
            while let c = peek(), isNameChar(c) { advance() }
            return String(chars[start..<i])
        }

        private func isNameChar(_ c: Character) -> Bool {
            if c == "\n" || c.isWhitespace { return false }
            return !"[]{},#".contains(c)
        }

        private mutating func parseDirective() -> Bool {
            guard column == 0, peek() == "%" else { return fail("directive") }
            advance()
            let start = i
            while let c = peek(), c != " " && c != "\t" && c != "\n" && c != "#" { advance() }
            guard i > start else { return fail("empty directive") }
            while let c = peek(), c != "\n", c != "#" {
                if c == "\t" { return fail("tab in a directive") }
                advance()
            }
            return finishLine()
        }

        // MARK: Whitespace and markers

        private mutating func skipStructure() -> Bool {
            while i < chars.count {
                if column != 0 { return true }
                while peek() == " " { advance() }
                if peek() == "\t" { return fail("tab indentation") }
                if peek() == "#" {
                    while let c = peek(), c != "\n" { advance() }
                    if peek() == "\n" { advance() }
                    continue
                }
                if peek() == "\n" { advance(); continue }
                return true
            }
            return true
        }

        @discardableResult
        private mutating func skipSameLineSpaces() -> Bool {
            while peek() == " " { advance() }
            if peek() == "\t" { return fail("tab") }
            return true
        }

        private mutating func skipFlowSpace() -> Bool {
            while i < chars.count {
                if peek() == " " || peek() == "\n" { advance(); continue }
                if peek() == "\t" { return fail("tab in a flow collection") }
                if peek() == "#" {
                    while let c = peek(), c != "\n" { advance() }
                    continue
                }
                return true
            }
            return true
        }

        private mutating func finishLine() -> Bool {
            while peek() == " " || peek() == "\t" { advance() }
            if peek() == "#" {
                while let c = peek(), c != "\n" { advance() }
            }
            if peek() == "\n" { advance(); return true }
            if i >= chars.count { return true }
            return fail("unexpected characters")
        }

        private mutating func consumeEntireLine() -> Bool {
            while let c = peek(), c != "\n" { advance() }
            if peek() == "\n" { advance() }
            return true
        }

        private func isBlankLine() -> Bool {
            var offset = 0
            while peek(offset) == " " { offset += 1 }
            if peek(offset) == "\t" { return false }
            let next = peek(offset)
            return next == "\n" || next == nil
        }

        private func isCommentLine() -> Bool {
            var offset = 0
            while peek(offset) == " " { offset += 1 }
            return peek(offset) == "#"
        }

        private func leadingSpaces() -> Int? {
            var offset = 0
            while peek(offset) == " " { offset += 1 }
            if peek(offset) == "\t" { return nil }
            return offset
        }

        private func isAtMarker(_ marker: String) -> Bool {
            guard column == 0, hasPrefix(marker) else { return false }
            return isBoundary(marker.count)
        }

        private mutating func consumeMarkerToken(_ marker: String) -> Bool {
            guard isAtMarker(marker) else { return fail("expected \(marker)") }
            for _ in marker { advance() }
            return true
        }

        private func lineHasPlainKey() -> Bool {
            var offset = 0
            var any = false
            while let c = peek(offset), c != "\n" {
                if c == "#" && (offset == 0 || peek(offset - 1) == " " || peek(offset - 1) == "\t") { return false }
                if c == ":" && isValueColon(offset) { return any }
                if c != " " && c != "\t" { any = true }
                offset += 1
            }
            return false
        }

        private func isValueColon(_ offset: Int) -> Bool {
            guard peek(offset) == ":" else { return false }
            let next = peek(offset + 1)
            return next == nil || next == " " || next == "\t" || next == "\n" || next == "#"
        }

        private func isFlowColon() -> Bool {
            guard peek() == ":" else { return false }
            let next = peek(1)
            return next == nil || next == " " || next == "\t" || next == "\n" || next == "#" || next == "," || next == "}" || next == "]"
        }

        private func isBoundary(_ offset: Int) -> Bool {
            guard let next = peek(offset) else { return true }
            return next == " " || next == "\t" || next == "\n" || next == "#"
        }

        private func isAtLineEnd() -> Bool {
            var offset = 0
            while peek(offset) == " " || peek(offset) == "\t" { offset += 1 }
            let next = peek(offset)
            return next == nil || next == "\n" || next == "#"
        }

        private func isCommentStart() -> Bool {
            if i == 0 { return true }
            let previous = chars[i - 1]
            return previous == " " || previous == "\t" || previous == "\n"
        }

        private func previousSignificantOnLine() -> Character? {
            var index = i - 1
            while index >= 0 && chars[index] != "\n" {
                if chars[index] != " " && chars[index] != "\t" { return chars[index] }
                index -= 1
            }
            return nil
        }

        private func hasPriorContentOnLine() -> Bool {
            var index = i - 1
            while index >= 0 && chars[index] != "\n" {
                if chars[index] != " " && chars[index] != "\t" { return true }
                index -= 1
            }
            return false
        }

        private func hasPrefix(_ prefix: String) -> Bool {
            for (offset, character) in prefix.enumerated() where peek(offset) != character { return false }
            return true
        }

        private mutating func consumeHex(_ count: Int) -> Bool {
            for _ in 0..<count {
                guard let c = peek(), c.isHexDigit else { return fail("invalid hex escape") }
                advance()
            }
            return true
        }

        private func peek(_ offset: Int = 0) -> Character? {
            let index = i + offset
            return index < chars.count ? chars[index] : nil
        }

        private mutating func advance() {
            guard i < chars.count else { return }
            if chars[i] == "\n" {
                line += 1
                column = 0
            } else {
                column += 1
            }
            i += 1
        }

        private func here() -> Mark { Mark(i: i, line: line, column: column) }

        private mutating func restore(_ mark: Mark) {
            i = mark.i
            line = mark.line
            column = mark.column
        }

        private mutating func fail(_ message: String) -> Bool {
            if reason == nil { reason = "\(message) at \(line):\(column)" }
            return false
        }
    }
}
