import QuickLookThumbnailing
import AppKit

/// Draws a styled "card" thumbnail for Markdown files shown in Finder.
final class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let url = request.fileURL
        let size = request.maximumSize

        let ext = url.pathExtension.lowercased()
        guard ["md", "markdown", "mdown", "mkd", "mkdn"].contains(ext) else {
            handler(nil, nil)
            return
        }

        // Read the file off the main thread; the drawing block runs on main.
        DispatchQueue.global(qos: .userInitiated).async {
            // Check file size before reading
            guard let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
                  fileSize <= RenderingConstants.maxFileSize else {
                let reply = QLThumbnailReply(contextSize: size) {
                    Self.drawOversized(in: size)
                    return true
                }
                handler(reply, nil)
                return
            }
            
            let raw = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
            let title = Self.title(in: raw)
            let snippet = Self.snippet(in: raw)

            let reply = QLThumbnailReply(contextSize: size) {
                Self.draw(title: title, snippet: snippet, in: size)
                return true
            }
            handler(reply, nil)
        }
    }

    // MARK: - Text extraction

    private static func title(in raw: String) -> String {
        for line in MarkdownText.stripFrontMatter(raw).components(separatedBy: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { continue }
            if s.hasPrefix("#") {
                let cleaned = s.trimmingCharacters(in: CharacterSet(charactersIn: "# \t"))
                if !cleaned.isEmpty { return cleaned }
            } else if !s.hasPrefix("```") {
                return plain(s)
            }
        }
        return ""
    }

    private static func snippet(in raw: String) -> String {
        var lines: [String] = []
        for line in MarkdownText.stripFrontMatter(raw).components(separatedBy: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.isEmpty || s.hasPrefix("#") || s.hasPrefix("```") || s == "---" { continue }
            let p = plain(s)
            if !p.isEmpty { lines.append(p) }
            if lines.count >= 4 { break }
        }
        return lines.joined(separator: " · ")
    }

    private static func plain(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "`", with: "")
        t = t.replacingOccurrences(of: "!\\[[^\\]]*\\]\\([^)]*\\)", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\[[^\\]]*\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "[*_~]{1,3}", with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Drawing

    private static func drawOversized(in size: CGSize) {
        let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        let bg = dark ? NSColor(calibratedWhite: 0.10, alpha: 1) : NSColor(calibratedWhite: 0.97, alpha: 1)
        let fg = dark ? NSColor(calibratedWhite: 0.92, alpha: 1) : NSColor(calibratedWhite: 0.12, alpha: 1)
        let accent = NSColor(calibratedRed: 0.90, green: 0.46, blue: 0.10, alpha: 1)
        
        bg.setFill()
        NSBezierPath(roundedRect: CGRect(origin: .zero, size: size), xRadius: 5, yRadius: 5).fill()
        
        accent.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: size.height - 4, width: size.width, height: 4)).fill()
        
        let pad = max(10, size.width * 0.08)
        let text = "File too large"
        let font = NSFont.systemFont(ofSize: max(11, size.width * 0.06), weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg]
        let rect = CGRect(x: pad, y: size.height / 2 - 12, width: size.width - pad * 2, height: 24)
        NSAttributedString(string: text, attributes: attrs)
            .draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private static func draw(title: String, snippet: String, in size: CGSize) {
        let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        let bg = dark ? NSColor(calibratedWhite: 0.10, alpha: 1) : NSColor(calibratedWhite: 0.97, alpha: 1)
        let fg = dark ? NSColor(calibratedWhite: 0.92, alpha: 1) : NSColor(calibratedWhite: 0.12, alpha: 1)
        let sub = dark ? NSColor(calibratedWhite: 0.62, alpha: 1) : NSColor(calibratedWhite: 0.42, alpha: 1)
        let accent = NSColor(calibratedRed: 0.10, green: 0.46, blue: 0.90, alpha: 1)

        let pad = max(10, size.width * 0.08)

        bg.setFill()
        NSBezierPath(roundedRect: CGRect(origin: .zero, size: size), xRadius: 5, yRadius: 5).fill()

        // Top accent stripe
        accent.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: size.height - 4, width: size.width, height: 4)).fill()

        // Title
        var top = size.height - pad
        if !title.isEmpty {
            let font = NSFont.systemFont(ofSize: max(11, size.width * 0.06), weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg]
            let rect = CGRect(x: pad, y: top - 22, width: size.width - pad * 2, height: 24)
            NSAttributedString(string: title, attributes: attrs)
                .draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            top -= 30
        }

        // Snippet
        if !snippet.isEmpty {
            let font = NSFont.systemFont(ofSize: max(8, size.width * 0.045), weight: .regular)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: sub]
            let rect = CGRect(x: pad, y: pad, width: size.width - pad * 2, height: max(0, top - pad))
            NSAttributedString(string: snippet, attributes: attrs)
                .draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }

        // "MD" badge, bottom right
        let badge = NSAttributedString(
            string: "MD",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: max(9, size.width * 0.055), weight: .bold),
                .foregroundColor: accent
            ]
        )
        let badgeSize = badge.size()
        badge.draw(at: CGPoint(x: size.width - pad - badgeSize.width, y: pad))
    }
}
