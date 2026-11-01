import AppKit

/// Renders a standalone YAML document in the same monospaced panel as a fenced
/// code block. Valid documents within the highlighter budget are colored with
/// the existing YAML lexer. Anything oversized, non-UTF-8, or structurally
/// rejected stays plain monospaced text.
enum YAMLPreview {
    static func attributedString(from source: String, fontSize: CGFloat = 14, forcePlain: Bool = false) -> NSAttributedString {
        let out = CodeBlockStyle.panelString(source, fontSize: fontSize, blockID: 1)
        if !forcePlain, shouldHighlight(source) {
            SyntaxHighlighter.highlight(out, code: source, language: .yaml)
        }
        return out
    }

    static func shouldHighlight(_ source: String) -> Bool {
        let length = (source as NSString).length
        guard length > 0,
              length <= SyntaxHighlighter.maxBlockLength,
              length <= SyntaxHighlighter.maxDocumentLength else { return false }
        return YAMLValidator.isValid(source)
    }
}
