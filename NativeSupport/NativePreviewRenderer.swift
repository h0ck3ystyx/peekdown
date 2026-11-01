import AppKit
import BeautifulMermaid
import SwiftMath

/// Experimental image renderers. No document scripts, imports, or network requests.
public enum NativePreviewRenderer {
    public static func diagram(_ source: String, dark: Bool) -> NSImage? {
        // Start with two useful diagram families and a deliberately small budget.
        let lines = source.split(separator: "\n")
        guard source.utf16.count <= 4096, lines.count <= 48, source.filter({ $0 == ";" || $0 == ">" }).count <= 48,
              let first = lines.first?.trimmingCharacters(in: .whitespaces),
              first.hasPrefix("flowchart ") || first.hasPrefix("graph ") || first == "sequenceDiagram",
              !source.contains("%%{"), !source.contains("---"),
              !source.contains("click "), !source.contains("style "), !source.contains("classDef "),
              !source.contains("<"), !source.contains("@{") else { return nil }
        let renderer = MermaidImageRenderer(theme: dark ? .githubDark : .githubLight)
        guard let prepared = try? renderer.prepare(from: source), prepared.bounds.width.isFinite,
              prepared.bounds.height.isFinite, prepared.bounds.width <= 4096, prepared.bounds.height <= 4096 else { return nil }
        let scale = min(1, 700 / prepared.bounds.width, 500 / prepared.bounds.height)
        let size = CGSize(width: prepared.bounds.width * scale, height: prepared.bounds.height * scale)
        guard let context = CGContext(data: nil, width: Int(ceil(size.width * 2)),
                                      height: Int(ceil(size.height * 2)), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Mermaid expects a top-left origin. Its label renderer must also use
        // this bitmap context rather than the surrounding TextKit destination.
        context.translateBy(x: 0, y: CGFloat(context.height))
        context.scaleBy(x: scale * 2, y: -scale * 2)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = nil
        prepared.render(context, prepared.bounds)
        guard let bitmap = context.makeImage() else { return nil }
        return NSImage(cgImage: bitmap, size: size)
    }

    public static func math(_ source: String, size: CGFloat, dark: Bool) -> NSImage? {
        // Avoid the dependency's fatal missing-resource path if a package is incomplete.
        let bundle = Bundle.main.bundleURL.appendingPathComponent("SwiftMath_SwiftMath.bundle")
        guard FileManager.default.fileExists(atPath: bundle.path) || Bundle.main.url(forResource: "SwiftMath_SwiftMath", withExtension: "bundle") != nil else { return nil }
        guard source.utf16.count <= 1024 else { return nil }
        var depth = 0
        for char in source {
            if char == "{" { depth += 1; if depth > 16 { return nil } }
            if char == "}" { depth -= 1; if depth < 0 { return nil } }
        }
        guard depth == 0 else { return nil }
        let math = MTMathImage(latex: source, fontSize: size, textColor: dark ? .white : .black)
        let (error, image) = math.asImage()
        guard error == nil, let image = image, image.size.width.isFinite, image.size.height.isFinite,
              image.size.width > 0, image.size.width <= 4096, image.size.height > 0, image.size.height <= 2048 else { return nil }
        return image
    }
}
