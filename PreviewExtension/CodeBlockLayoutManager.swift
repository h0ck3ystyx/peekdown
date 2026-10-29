import AppKit

extension NSAttributedString.Key {
    static let peekdownCodeBlock = NSAttributedString.Key("PeekdownCodeBlock")
    static let peekdownCodeBackground = NSAttributedString.Key("PeekdownCodeBackground")
}

/// Draw one rounded panel per code block, behind selection and inline backgrounds.
/// Glyph positions remain native TextKit layout, including wrapping and scrolling.
final class CodeBlockLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, storage.length > 0, glyphsToShow.length > 0 else {
            super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        let visible = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        var index = visible.location
        while index < NSMaxRange(visible) {
            var range = NSRange()
            let marker = storage.attribute(.peekdownCodeBlock, at: index, longestEffectiveRange: &range,
                                           in: NSRange(location: 0, length: storage.length))
            if marker != nil, let color = storage.attribute(.peekdownCodeBackground, at: index, effectiveRange: nil) as? NSColor {
                // Only lay out the requested portion, even for a very large plain block.
                // The padding extends rounded ends beyond the dirty/visible region
                // when the true start or end of a block is offscreen.
                let glyphs = glyphRange(forCharacterRange: NSIntersectionRange(range, visible), actualCharacterRange: nil)
                if glyphs.length > 0, let container = textContainer(forGlyphAt: glyphs.location, effectiveRange: nil) {
                    let first = lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                    let last = lineFragmentUsedRect(forGlyphAt: NSMaxRange(glyphs)-1, effectiveRange: nil)
                    let paragraph = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
                    let indent = max(0, (paragraph?.headIndent ?? 12)-12)
                    let left = container.lineFragmentPadding + indent
                    let width = max(0, container.size.width - left - container.lineFragmentPadding)
                    let panel = NSRect(x: origin.x+left, y: origin.y+first.minY-8,
                                       width: width, height: last.maxY-first.minY+16)
                    color.setFill()
                    NSBezierPath(roundedRect: panel, xRadius: 6, yRadius: 6).fill()
                }
            }
            index = max(index+1, NSMaxRange(range))
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }
}
