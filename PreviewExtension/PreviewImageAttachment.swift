import AppKit

/// Shrink display images to the current line width without stretching them.
final class PreviewImageAttachment: NSTextAttachment {
    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: NSRect,
                                   glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        guard let image = image else { return .zero }
        let available = max(1, lineFrag.width - 2*(textContainer?.lineFragmentPadding ?? 5))
        let scale = min(1, available / max(1, image.size.width))
        return NSRect(x: 0, y: 0, width: image.size.width*scale, height: image.size.height*scale)
    }
}
