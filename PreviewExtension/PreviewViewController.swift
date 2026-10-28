import Cocoa
import QuickLookUI

/// View-based Quick Look preview: renders Markdown to NSAttributedString and
/// shows it in an NSTextView without WebKit or JavaScript.
final class PreviewViewController: NSViewController, QLPreviewingController {

    private let textView = NSTextView()

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        self.view = scrollView
        self.preferredContentSize = NSSize(width: 780, height: 560)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        // Reject unexpected requests rather than reporting an empty successful preview.
        let ext = url.pathExtension.lowercased()
        guard ["md", "markdown", "mdown", "mkd", "mkdn"].contains(ext) else {
            handler(NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError,
                            userInfo: [NSLocalizedDescriptionKey: "Unsupported file type"]))
            return
        }
        
        // Check file size before reading
        guard let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              fileSize <= RenderingConstants.maxFileSize else {
            let fallback = """
                File Too Large
                
                This Markdown file exceeds the \(RenderingConstants.maxFileSize / 1024 / 1024) MB preview limit.
                Please open it in a text editor.
                """
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            textView.textStorage?.setAttributedString(NSAttributedString(string: fallback, attributes: attrs))
            handler(nil)
            return
        }
        
        let raw: String
        if let s = try? String(contentsOf: url, encoding: .utf8) {
            raw = s
        } else {
            raw = (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
        }

        let attributed = MarkdownRenderer.attributedString(from: raw)
        textView.textStorage?.setAttributedString(attributed)
        handler(nil)
    }
}
