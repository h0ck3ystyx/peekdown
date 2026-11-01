import Cocoa
import QuickLookUI
import os

private let linkLog = Logger(subsystem: "com.markdownpreview.app.preview", category: "links")

/// View-based Quick Look preview: renders Markdown or YAML to NSAttributedString
/// and shows it in an NSTextView without WebKit or JavaScript.
final class PreviewViewController: NSViewController, QLPreviewingController, NSTextViewDelegate {

    private let textView: NSTextView = {
        let storage = NSTextStorage()
        let layout = CodeBlockLayoutManager()
        let container = NSTextContainer()
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        return NSTextView(frame: .zero, textContainer: container)
    }()
    private let linkStatus = NSTextField(wrappingLabelWithString: "")
    private let linkBanner = NSStackView()
    private lazy var copyLinkButton = NSButton(title: "Copy link", target: self, action: #selector(copyFailedLink))
    private var failedLink: URL?
    private lazy var linkHandler = PreviewLinkHandler { [weak self] url in
        self?.linkBanner.isHidden = true
        // Ask the host to open the destination on our behalf. Launching apps
        // directly from a Quick Look extension can be denied by its sandbox.
        let opener = PreviewURLOpener(
            requestOpen: { url, completion in
                guard let context = self?.extensionContext else {
                    linkLog.notice("URL click has no extension context")
                    completion(false)
                    return
                }
                context.open(url) { success in
                    linkLog.notice("Host URL opening succeeded: \(success)")
                    completion(success)
                }
            },
            fallbackOpen: { url, completion in
                NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    let code = (error as NSError?)?.code ?? 0
                    let domain = (error as NSError?)?.domain ?? "none"
                    let underlying = (error as NSError?)?.userInfo[NSUnderlyingErrorKey] as? NSError
                    let underlyingDomain = underlying?.domain ?? "none"
                    let underlyingCode = underlying?.code ?? 0
                    linkLog.notice("Workspace URL opening: \(domain, privacy: .public) \(code), underlying \(underlyingDomain, privacy: .public) \(underlyingCode)")
                    completion(error == nil)
                }
            },
            onFailure: { [weak self] in
                linkLog.error("Both host and workspace URL opening failed")
                DispatchQueue.main.async { self?.showLinkFailure(url) }
            }
        )
        opener.open(url)
    }

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.delegate = self
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
        linkStatus.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        linkStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        copyLinkButton.setContentHuggingPriority(.required, for: .horizontal)
        linkBanner.orientation = .horizontal
        linkBanner.spacing = 10
        linkBanner.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        linkBanner.addArrangedSubview(linkStatus)
        linkBanner.addArrangedSubview(copyLinkButton)
        linkBanner.isHidden = true

        let content = NSStackView(views: [scrollView, linkBanner])
        content.orientation = .vertical
        content.spacing = 0
        content.alignment = .leading
        content.frame = NSRect(x: 0, y: 0, width: 780, height: 560)
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        linkBanner.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        self.view = content
        self.preferredContentSize = NSSize(width: 780, height: 560)
    }

    private func showLinkFailure(_ url: URL) {
        failedLink = url
        linkStatus.stringValue = "macOS couldn’t open this link from Quick Look. Copy it to open in your browser or email app."
        copyLinkButton.title = "Copy link"
        linkBanner.isHidden = false
    }

    @objc private func copyFailedLink() {
        guard let url = failedLink else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(url.absoluteString, forType: .string) {
            linkStatus.stringValue = "Link copied. Paste it into your browser or email app."
        } else {
            linkStatus.stringValue = "The link couldn’t be copied. Select the link text and use Copy from the context menu."
        }
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        linkHandler.handle(link)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        linkBanner.isHidden = true
        failedLink = nil
        // Reject unexpected requests rather than reporting an empty successful preview.
        guard let kind = PreviewDocumentKind.kind(for: url) else {
            handler(NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError,
                            userInfo: [NSLocalizedDescriptionKey: "Unsupported file type"]))
            return
        }

        let settings = PreviewSettings.load()
        // A single bounded read enforces the limit even if the file changes.
        guard let loaded = PreviewFileReader.read(url: url, maxBytes: nil) else {
            handler(NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError))
            return
        }
        if kind != .yaml {
            guard !loaded.isTruncated else {
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
            let raw = kind == .mdx ? StaticMDX.markdownView(of: loaded.text) : loaded.text
            textView.textStorage?.setAttributedString(MarkdownRenderer.attributedString(from: raw, settings: settings))
            handler(nil)
            return
        }

        if loaded.isTruncated {
            let prefix = loaded.text
            let note = "\n\n— Preview truncated. This YAML file exceeds the \(RenderingConstants.maxFileSize / 1024 / 1024) MB limit and is shown as plain text. —\n"
            textView.textStorage?.setAttributedString(YAMLPreview.attributedString(from: prefix + note, forcePlain: true, settings: settings))
            handler(nil)
            return
        }
        let raw = loaded.text
        textView.textStorage?.setAttributedString(
            YAMLPreview.attributedString(from: raw, forcePlain: !loaded.isUTF8, settings: settings)
        )
        handler(nil)
    }
}

enum PreviewDocumentKind {
    case markdown
    case mdx
    case yaml

    static func kind(for url: URL) -> PreviewDocumentKind? {
        switch url.pathExtension.lowercased() {
        case "md", "markdown", "mdown", "mkd", "mkdn":
            return .markdown
        case "mdx":
            return .mdx
        case "yaml", "yml":
            return .yaml
        default:
            return nil
        }
    }
}

enum PreviewFileReader {
    struct Text {
        var text: String
        var isUTF8: Bool
        var isTruncated = false
    }

    static func read(url: URL, maxBytes: Int?) -> Text? {
        let limit = maxBytes ?? RenderingConstants.maxFileSize
        guard limit >= 0, limit < Int.max,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // Read one overflow byte from the same descriptor; never reopen by path.
        guard let data = try? handle.read(upToCount: limit + 1) else { return nil }
        let truncated = data.count > limit
        let retained = truncated ? min(limit, SyntaxHighlighter.maxDocumentLength) : data.count
        var result = decode(Data(data.prefix(retained)), repairTruncatedTail: truncated)
        result.isTruncated = truncated
        return result
    }

    static func decode(_ data: Data, repairTruncatedTail: Bool = false) -> Text {
        if let text = String(data: data, encoding: .utf8) {
            return Text(text: text, isUTF8: true)
        }
        // A bounded read can split a code unit. Drop that incomplete tail, and
        // only then, before treating the bytes as a non-UTF-8 encoding.
        if repairTruncatedTail {
            var trimmed = data
            let floor = max(0, data.count - 3)
            while trimmed.count > floor && String(data: trimmed, encoding: .utf8) == nil {
                trimmed.removeLast()
            }
            if trimmed.count < data.count, let text = String(data: trimmed, encoding: .utf8) {
                return Text(text: text, isUTF8: true)
            }
        }
        return Text(text: String(data: data, encoding: .isoLatin1) ?? "", isUTF8: false)
    }
}

/// Some Quick Look hosts decline NSExtensionContext.open. Try the public
/// LaunchServices route only after a host refusal, without an audible alert.
struct PreviewURLOpener {
    let requestOpen: (URL, @escaping (Bool) -> Void) -> Void
    let fallbackOpen: (URL, @escaping (Bool) -> Void) -> Void
    let onFailure: () -> Void

    func open(_ url: URL) {
        requestOpen(url) { success in
            guard !success else { return }
            let fallback = { fallbackOpen(url) { if !$0 { onFailure() } } }
            if Thread.isMainThread { fallback() }
            else { DispatchQueue.main.async(execute: fallback) }
        }
    }
}

/// Keep URL conversion and click handling testable without launching applications.
struct PreviewLinkHandler {
    let openURL: (URL) -> Void

    func handle(_ link: Any) -> Bool {
        let url: URL?
        if let value = link as? URL { url = value }
        else if let value = link as? String { url = URL(string: value) }
        else { url = nil }

        if let url = url, let scheme = url.scheme?.lowercased(),
           ["http", "https", "mailto"].contains(scheme),
           (scheme == "mailto" ? !url.path.isEmpty : url.host?.isEmpty == false) {
            openURL(url)
        }
        // Always consume the click, including unsupported schemes, so AppKit
        // does not attempt a second launch through its default responder path.
        return true
    }
}
