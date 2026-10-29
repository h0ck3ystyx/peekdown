import AppKit

/// A bounded, offline lexical highlighter. Never evaluates code or loads grammars.
enum SyntaxHighlighter {
    static let maxBlockLength = 64 * 1024 // UTF-16 units
    static let maxTokens = 8192
    static let maxDocumentLength = 256 * 1024

    enum Language: String {
        case swift, shell, json, yaml, python, javascript, typescript
        init?(hint: String) {
            // Use only the first fence info word; attributes never become code.
            let word = hint.prefix(128).split(maxSplits: 1, whereSeparator: { $0.isWhitespace }).first.map(String.init)?.lowercased() ?? ""
            switch word {
            case "swift": self = .swift
            case "sh", "shell", "bash", "zsh": self = .shell
            case "json": self = .json
            case "yaml", "yml": self = .yaml
            case "python", "py": self = .python
            case "javascript", "js": self = .javascript
            case "typescript", "ts": self = .typescript
            default: return nil
            }
        }
        var keywords: Set<String> {
            let words: String
            switch self {
            case .swift:
                words = "actor associatedtype async await as any borrowing break case catch class consuming continue convenience copy default defer deinit didSet distributed do dynamic each else enum extension fallthrough false fileprivate final for func get guard if import in indirect infix init inout internal is isolated lazy let macro mutating nil nonisolated nonmutating open operator optional override package postfix precedencegroup prefix private protocol public repeat required rethrows return self Self sending set some static struct subscript super switch throws throw true try typealias unowned var weak where while willSet"
            case .shell:
                words = "if then else elif fi for while until do done case esac in function select time coproc export local readonly declare typeset unset return break continue echo printf cd source eval exec exit test"
            case .json, .yaml: words = "true false null" + (self == .yaml ? " True False NULL Null TRUE FALSE yes no on off" : "")
            case .python:
                words = "False None True and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case"
            case .javascript, .typescript:
                words = "async await break case catch class const continue debugger default delete do else export extends false finally for from function get if import in instanceof let new null of return set static super switch this throw true try typeof undefined var void while with yield" + (self == .typescript ? " abstract any as asserts boolean constructor declare enum implements infer interface is keyof module namespace never number private protected public readonly require satisfies string symbol type unknown" : "")
            }
            return Set(words.split(separator: " ").map(String.init))
        }
    }

    enum Kind: String, CaseIterable { case keyword, string, comment, number, type, property, variable }
    struct Token { let range: NSRange; let kind: Kind }

    private static let palette = Dictionary(uniqueKeysWithValues: Kind.allCases.map { ($0, makeColor(for: $0)) })

    static func color(for kind: Kind) -> NSColor { palette[kind]! }

    private static func makeColor(for kind: Kind) -> NSColor {
        // Dark colors on light backgrounds, lighter equivalents on dark backgrounds.
        let pair: (UInt32, UInt32)
        switch kind {
        case .keyword: pair = (0x7438A8, 0xD9A5FF)
        case .string: pair = (0x8F322B, 0xFFB4A9)
        case .comment: pair = (0x49634C, 0xA8C6AA)
        case .number: pair = (0x185DA8, 0x9CCAFF)
        case .type: pair = (0x00666D, 0x83D8DE)
        case .property: pair = (0x805000, 0xEAC47D)
        case .variable: pair = (0x8A3A70, 0xE8A6D0)
        }
        return NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? pair.1 : pair.0
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        }
    }

    /// UTF-16 offsets match NSAttributedString. All scans advance monotonically.
    static func tokens(in code: String, language: Language) -> [Token] {
        guard code.utf16.count <= maxBlockLength else { return [] }
        let units = Array(code.utf16)
        let count = units.count
        let words = language.keywords
        var result: [Token] = []
        var i = 0
        func at(_ index: Int) -> UInt16 { index < count ? units[index] : 0 }
        func letter(_ u: UInt16) -> Bool { (65...90).contains(u) || (97...122).contains(u) || u == 95 }
        func digit(_ u: UInt16) -> Bool { (48...57).contains(u) }
        func identifier(_ u: UInt16) -> Bool { letter(u) || digit(u) || u >= 128 }
        func matches(_ index: Int, _ first: UInt16, _ second: UInt16) -> Bool { at(index) == first && at(index + 1) == second }
        func emit(_ start: Int, _ kind: Kind) { result.append(Token(range: NSRange(location: start, length: i-start), kind: kind)) }
        let slashComments = [.swift, .javascript, .typescript].contains(language)
        while i < count {
            let start = i
            let u = units[i]
            let hashComment = (language == .python || language == .shell || language == .yaml) && u == 35 &&
                (language == .python || i == 0 || [UInt16(32), 9, 10, 13, 59].contains(at(i-1)))
            if hashComment || (slashComments && matches(i, 47, 47)) {
                while i < count && at(i) != 10 && at(i) != 13 { i += 1 }
                emit(start, .comment)
            } else if slashComments && matches(i, 47, 42) {
                i += 2
                var depth = 1
                while i < count && depth > 0 {
                    if language == .swift && matches(i, 47, 42) { depth += 1; i += 2 }
                    else if matches(i, 42, 47) { depth -= 1; i += 2 }
                    else { i += 1 }
                }
                emit(start, .comment)
            } else if u == 34 || (u == 39 && language != .json && language != .swift) ||
                        (u == 96 && (language == .javascript || language == .typescript)) {
                let triple = (language == .python || language == .swift) && at(i+1) == u && at(i+2) == u
                i += triple ? 3 : 1
                while i < count {
                    if at(i) == 92 && !(language == .shell && u == 39) && !(language == .yaml && u == 39) {
                        i = min(i+2, count)
                    } else if at(i) == u {
                        if triple {
                            if at(i+1) == u && at(i+2) == u { i += 3; break }
                            i += 1
                        } else if language == .yaml && u == 39 && at(i+1) == u { i += 2 }
                        else { i += 1; break }
                    } else if !triple && at(i) == 10 && language != .shell && u != 96 { break }
                    else { i += 1 }
                }
                var next = i
                while at(next) == 32 || at(next) == 9 { next += 1 }
                emit(start, (language == .json || language == .yaml) && at(next) == 58 ? .property : .string)
            } else if language == .shell && u == 36 && (letter(at(i+1)) || at(i+1) == 123 || digit(at(i+1))) {
                i += 1
                if at(i) == 123 {
                    i += 1
                    while i < count && at(i) != 125 && at(i) != 10 { i += 1 }
                    if at(i) == 125 { i += 1 }
                } else { while i < count && identifier(at(i)) { i += 1 } }
                emit(start, .variable)
            } else if digit(u) && (i == 0 || !identifier(at(i-1))) {
                i += 1
                if u == 48 && [UInt16(120), 88, 98, 66, 111, 79].contains(at(i)) {
                    i += 1
                    while digit(at(i)) || (65...70).contains(at(i)) || (97...102).contains(at(i)) || at(i) == 95 { i += 1 }
                } else {
                    while digit(at(i)) || at(i) == 95 { i += 1 }
                    if at(i) == 46 && digit(at(i+1)) { i += 1; while digit(at(i)) || at(i) == 95 { i += 1 } }
                    if at(i) == 101 || at(i) == 69 {
                        var end = i+1
                        if at(end) == 43 || at(end) == 45 { end += 1 }
                        if digit(at(end)) { i = end+1; while digit(at(i)) { i += 1 } }
                    }
                }
                emit(start, .number)
            } else if letter(u) || u >= 128 {
                i += 1
                while i < count && (identifier(at(i)) || (language == .yaml && at(i) == 45)) { i += 1 }
                let word = String(decoding: units[start..<i], as: UTF16.self)
                var next = i
                while at(next) == 32 || at(next) == 9 { next += 1 }
                if words.contains(word) { emit(start, .keyword) }
                else if language == .yaml && at(next) == 58 { emit(start, .property) }
                else if (language == .swift || language == .python || language == .javascript || language == .typescript) && (65...90).contains(u) {
                    emit(start, .type)
                }
            } else { i += 1 }
            if result.count > maxTokens { return [] }
        }
        return result
    }

    static func highlight(_ output: NSMutableAttributedString, code: String, language: Language) {
        for token in tokens(in: code, language: language) {
            output.addAttribute(.foregroundColor, value: color(for: token.kind), range: token.range)
        }
    }
}
