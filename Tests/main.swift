import AppKit

// MARK: - Front matter tests

let frontMatterCases: [(String, String)] = [
    ("---\ntitle: Example\n---", ""),
    ("---\n---\n# Body", "# Body"),
    ("---\ntitle: Example\n---\nHello", "Hello"),
    ("---\ntitle: Example\n...\nHello", "Hello"),
    ("---\r\ntitle: Example\r\n---\r\nHello", "Hello"),
    ("---\rtitle: Example\r---\rHello", "Hello"),
    ("---\nunclosed", "---\nunclosed"),
    ("---not front matter\n---\nHello", "---not front matter\n---\nHello"),
    ("Text\n---\nMore", "Text\n---\nMore"),
    ("---\ntitle: Example\n---suffix\nBody", "---\ntitle: Example\n---suffix\nBody"),
    ("", "")
]

for (input, expected) in frontMatterCases {
    precondition(MarkdownText.stripFrontMatter(input) == expected, "Front matter mismatch: \(input.debugDescription)")
    _ = MarkdownRenderer.attributedString(from: input)
}

let rendered = MarkdownRenderer.attributedString(from: "---\ntitle: hidden\n---\n# Visible")
precondition(rendered.string.contains("Visible") && !rendered.string.contains("hidden"))

// MARK: - Non-Markdown rejection

var rejected = false
let controller = PreviewViewController()
controller.preparePreviewOfFile(at: URL(fileURLWithPath: "/tmp/unrelated.txt")) { error in
    rejected = error != nil
}
precondition(rejected, "Non-Markdown request must not return a blank successful preview")

// MARK: - Link scheme validation tests

// Test a few key cases
let httpTest = MarkdownRenderer.attributedString(from: "[link](http://example.com)")
let httpsTest = MarkdownRenderer.attributedString(from: "[link](https://example.com)")
let javascriptTest = MarkdownRenderer.attributedString(from: "[link](javascript:alert(1))")
let absolutePathTest = MarkdownRenderer.attributedString(from: "[link](/Applications/Calculator.app)")
let relativePathTest = MarkdownRenderer.attributedString(from: "[link](../../evil)")
let tildePathTest = MarkdownRenderer.attributedString(from: "[link](~/Downloads/x.command)")
let protocolRelativeTest = MarkdownRenderer.attributedString(from: "[link](//host/path)")
let malformedHttpsTest = MarkdownRenderer.attributedString(from: "[link](https:)")

// Just verify they render without crashing - actual clickability tested manually
precondition(httpTest.length > 0, "http test failed to render")
precondition(httpsTest.length > 0, "https test failed to render")
precondition(javascriptTest.length > 0, "javascript test failed to render")
precondition(absolutePathTest.length > 0, "absolute path test failed to render")
precondition(relativePathTest.length > 0, "relative path test failed to render")
precondition(tildePathTest.length > 0, "tilde path test failed to render")
precondition(protocolRelativeTest.length > 0, "protocol-relative test failed to render")
precondition(malformedHttpsTest.length > 0, "malformed https test failed to render")

// MARK: - Table separator ReDoS protection test

func measureTableSeparatorPerformance() -> TimeInterval {
    let start = CFAbsoluteTimeGetCurrent()
    // Create a pathological line that would cause catastrophic backtracking without the guard
    let pathologicalLine = String(repeating: "|:---", count: 5000) + "x"
    _ = MarkdownRenderer.attributedString(from: "# Header\n\(pathologicalLine)\n# Footer")
    return CFAbsoluteTimeGetCurrent() - start
}

let tablePerfTime = measureTableSeparatorPerformance()
// Should complete quickly (under 0.5 seconds) with the line-length guard
precondition(tablePerfTime < 0.5, "Table separator regex performance test failed: took \(tablePerfTime)s (should be < 0.5s)")

// MARK: - File size limit constant validation

// Verify the file size constant is reasonable (10 MB)
precondition(RenderingConstants.maxFileSize == 10 * 1024 * 1024, "Max file size should be 10 MB")

// MARK: - Summary

print("✅ Passed \(frontMatterCases.count) front-matter cases")
print("✅ Passed renderer integration and non-Markdown rejection")
print("✅ Passed 8 link scheme validation tests")
print("✅ Passed table separator ReDoS protection test (completed in \(String(format: "%.3f", tablePerfTime))s)")
print("✅ Validated file size limit constant")
print("All tests passed!")


// Inspect the attributed output rather than only its plain text: links, superscript
// references, emphasis, and dynamic callout colors are the behavior under test.
func render(_ source: String) -> NSAttributedString {
    MarkdownRenderer.attributedString(from: source)
}
func links(_ text: NSAttributedString) -> [(String, String)] {
    var result: [(String, String)] = []
    text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, range, _ in
        if let value = value { result.append(((text.string as NSString).substring(with: range), String(describing: value))) }
    }
    return result
}
func attribute(_ key: NSAttributedString.Key, at needle: String, in text: NSAttributedString) -> Any? {
    let range = (text.string as NSString).range(of: needle)
    precondition(range.location != NSNotFound, "Missing rendered text: \(needle)")
    return text.attribute(key, at: range.location, effectiveRange: nil)
}
let fixture = try String(contentsOfFile: "Tests/Fixtures/issue-1.md", encoding: .utf8)
let rich = render(fixture)
let destinations = links(rich).map { $0.1 }
for expected in ["https://github.com/h0ck3ystyx/peekdown", "https://example.org/a_b", "http://www.example.org", "mailto:reader@example.org", "https://example.org/note", "https://example.org/table", "https://example.org/note-body"] {
    precondition(destinations.contains(expected), "Missing destination: \(expected)")
}
for excluded in ["https://example.org/fenced", "https://example.org/indented", "https://example.org/code", "https://example.org/escaped"] {
    precondition(!destinations.contains(excluded), "Literal code/escape unexpectedly linked: \(excluded)")
}
precondition(rich.string.contains("early reference[1]") && rich.string.contains("formatted reference[2]"))
precondition(rich.string.contains("repeated reference[1]") && rich.string.contains("undefined one[^missing]"))
precondition(rich.string.contains("1. This is the first numbered note.") && rich.string.contains("2. This is the second numbered note"))
precondition(rich.string.contains("3. A note referenced in a table."))
precondition(!rich.string.contains("This note should not appear"))
precondition(attribute(.superscript, at: "[1]", in: rich) as? Int == 1)
precondition(attribute(.superscript, at: "[^missing]", in: rich) == nil)
precondition(rich.string.contains("[^fenced]: Not a definition") && rich.string.contains("[^indented]: Also not a definition"))
precondition(rich.string.contains("Escaped: [^first], <https://example.org/escaped>, and *literal*."))
let bold = attribute(.font, at: "formatted reference", in: rich) as! NSFont
precondition(bold.fontDescriptor.symbolicTraits.contains(.bold))
for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
    NSAppearance(named: appearanceName)!.performAsCurrentDrawingAppearance {
        let sample = render(fixture)
        for label in ["ⓘ Note", "✓ Tip", "◆ Important", "⚠ Warning", "⛔ Caution"] {
            let color = attribute(.foregroundColor, at: label, in: sample) as! NSColor
            precondition(color.usingColorSpace(.deviceRGB) != nil)
            precondition(attribute(.backgroundColor, at: label, in: sample) != nil)
        }
        precondition(sample.string.contains("[!UNKNOWN]"))
        precondition(attribute(.backgroundColor, at: "[!UNKNOWN]", in: sample) == nil)
    }
}
let punctuation = links(render("(https://example.org/a_(b)). www.example.org/path! <https://example.org/a_(b)>"))
precondition(punctuation.map { $0.1 } == ["https://example.org/a_(b)", "http://www.example.org/path", "https://example.org/a_(b)"])
let explicit = links(render("[https://label.example/a_b](https://destination.example/a_(b))"))
precondition(explicit.count == 1 && explicit[0].0 == "https://label.example/a_b" && explicit[0].1 == "https://destination.example/a_(b)")
precondition(links(render("`https://example.org` ``https://example.org ` [^x]``\n\n[^x]: hidden")).isEmpty)
precondition(!render("`[^x]`\n\n[^x]: hidden").string.contains("Footnotes"))
let forward = render("[^b] [^a] [^b]\n\n[^a]: Alpha\n[^b]: Beta\n[^b]: Duplicate")
precondition(forward.string.hasPrefix("[1] [2] [1]") && !forward.string.contains("Duplicate"))
precondition(!render("[^a]").string.contains("Footnotes"), "Footnotes leaked across documents")
let cyclic = render("[^a]\n\n[^a]: Self[^a] and other[^b]\n[^b]: Back[^a]")
precondition(cyclic.string.components(separatedBy: "Self").count == 2 && cyclic.string.components(separatedBy: "Back").count == 2)
let malformed = ["[^", "[^]: empty", "[^a]:", "<http://>", "<bad@example>", "[broken](", "[!NOTE]", ">[!UNKNOWN]\n> text", "\\", String(repeating: ">", count: 100) + " text"]
for input in malformed { _ = render(input) }
// Surplus table cells used to exceed column widths. Exercise links and references
// through wrapping, including emoji whose UTF-16 ranges differ from character counts.
let table = render("| Header |\n| --- |\n| 😀 https://example.org/longlonglonglonglonglonglonglonglonglonglonglonglonglonglonglong | extra |")
precondition(links(table).map { $0.1 }.joined().contains("https://example.org/long"))
let large = String(repeating: "A paragraph with https://example.org and a note[^large].\n\n", count: 1500) + "[^large]: One definition."
let largeResult = render(large)
precondition(links(largeResult).count == 1500)
precondition(largeResult.string.components(separatedBy: "One definition.").count == 2)
_ = render(String(repeating: "[", count: 20_000))
let underscoreLabel = links(render("[https://example.org/snake_case_value](https://destination.example/)"))
precondition(underscoreLabel.count == 1 && underscoreLabel[0].0 == "https://example.org/snake_case_value")
precondition(render("snake_case_value and **bold** plus _italic_").string == "snake_case_value and bold plus italic\n")
precondition(render("x[^a]\n\n[^a]: Start\n  \n    continuation").string.contains("1. Start\ncontinuation\n"))

let malformedLarge = String(repeating: "_x", count: 10_000) + "@invalid"
precondition(links(render(malformedLarge)).isEmpty)
_ = render(String(repeating: "word ` unmatched ", count: 1000))
let styledEmails = render("**reader@example.org** and _other@example.org_")
precondition(links(styledEmails).map { $0.1 } == ["mailto:reader@example.org", "mailto:other@example.org"])
precondition(!styledEmails.string.contains("*") && !styledEmails.string.contains("_"))
let listCode = render("- ```\n  [^inside]: Literal code\n  ```\n\nOutside[^inside].")
precondition(listCode.string.contains("Outside[^inside]") && !listCode.string.contains("Footnotes"))

let afterList = render("- One item\n> [!NOTE]\n> Separate callout.")
precondition(afterList.string.contains("ⓘ Note") && afterList.string.contains("Separate callout."))
print("Passed autolink, footnote, alert, appearance, malformed-input, and large-document regressions")

// Exercise click dispatch independently of LaunchServices and the user's apps.
var openedLinks: [URL] = []
let clickHandler = PreviewLinkHandler { openedLinks.append($0) }
for link: Any in ["https://example.org/docs", URL(string: "http://example.org")!, "mailto:reader@example.org", NSURL(string: "https://example.org/bridged")!] {
    precondition(clickHandler.handle(link))
}
precondition(openedLinks.map { $0.absoluteString } == [
    "https://example.org/docs", "http://example.org", "mailto:reader@example.org", "https://example.org/bridged"
])
for link: Any in ["file:///tmp/example.md", "javascript:alert(1)", "custom-scheme:test", "relative/path", "https://", "mailto:", 42] {
    precondition(clickHandler.handle(link))
}
precondition(openedLinks.count == 4, "Unsupported links must not be dispatched")
controller.loadView()
let previewScrollView = (controller.view as! NSStackView).arrangedSubviews.first as! NSScrollView
let previewTextView = previewScrollView.documentView as! NSTextView
precondition(previewTextView.delegate === controller, "Link clicks must reach the preview controller")
print("Passed preview link routing and delegate-wiring checks")

let openingURL = URL(string: "https://example.org")!
for hostSuccess in [true, false] {
    for workspaceSuccess in [true, false] {
        var fallbackCount = 0
        var failureCount = 0
        let opener = PreviewURLOpener(
            requestOpen: { url, completion in precondition(url == openingURL); completion(hostSuccess) },
            fallbackOpen: { url, completion in precondition(url == openingURL); fallbackCount += 1; completion(workspaceSuccess) },
            onFailure: { failureCount += 1 }
        )
        opener.open(openingURL)
        precondition(fallbackCount == (hostSuccess ? 0 : 1))
        precondition(failureCount == (!hostSuccess && !workspaceSuccess ? 1 : 0))
    }
}
print("Passed host-refusal and workspace fallback checks")

for blocked in [javascriptTest, absolutePathTest, relativePathTest, tildePathTest, protocolRelativeTest, malformedHttpsTest] {
    precondition(links(blocked).isEmpty, "Blocked schemes and local paths must not acquire link attributes")
}
precondition(links(httpTest).first?.1 == "http://example.com")
precondition(links(httpsTest).first?.1 == "https://example.com")

// MARK: - Syntax highlighting
func syntaxTokens(_ code: String, _ language: SyntaxHighlighter.Language) -> [(String, SyntaxHighlighter.Kind)] {
    let source = code as NSString
    return SyntaxHighlighter.tokens(in: code, language: language).map { (source.substring(with: $0.range), $0.kind) }
}
let syntaxCases: [(SyntaxHighlighter.Language, String, String, SyntaxHighlighter.Kind)] = [
    (.swift, "let value: String = \"hello\" // note", "let", .keyword),
    (.swift, "/* outer /* nested */ end */ let n = 42", "/* outer /* nested */ end */", .comment),
    (.shell, "echo $HOME # note", "$HOME", .variable),
    (.json, "{\"enabled\": true, \"count\": 12}", "\"enabled\"", .property),
    (.yaml, "my-key: false # note", "my-key", .property),
    (.python, "def greeting():\n    return \"hi\"", "def", .keyword),
    (.python, "value = '''line\n# literal\nend'''", "'''line\n# literal\nend'''", .string),
    (.javascript, "const link = \"https://example.org\"; // note", "\"https://example.org\"", .string),
    (.typescript, "interface Person { age: number }", "interface", .keyword),
    (.swift, "let 😀 = 1; let value = 2.5e-3", "2.5e-3", .number)
]
for (language, code, expected, kind) in syntaxCases {
    precondition(syntaxTokens(code, language).contains { $0.0 == expected && $0.1 == kind }, "Missing \(kind) in \(language): \(expected)")
}
precondition(SyntaxHighlighter.Language(hint: "JS title=example") == .javascript)
precondition(SyntaxHighlighter.Language(hint: "YML") == .yaml)
precondition(SyntaxHighlighter.Language(hint: "unknown") == nil)
let protectedCode = syntaxTokens("// let false 42\n\"let false 42\"", .swift)
precondition(protectedCode.count == 2 && protectedCode[0].1 == .comment && protectedCode[1].1 == .string)
precondition(!syntaxTokens("letter", .swift).contains { $0.1 == .keyword })
precondition(!syntaxTokens("# not a JSON comment", .json).contains { $0.1 == .comment })
for malformed in ["/* unclosed", "\"unterminated\\", "\"\"\"unterminated", "${unclosed", String(repeating: "😀", count: 2000)] {
    for language in [SyntaxHighlighter.Language.swift, .python, .shell, .javascript] {
        var end = 0
        for token in SyntaxHighlighter.tokens(in: malformed, language: language) {
            precondition(token.range.location >= end && NSMaxRange(token.range) <= (malformed as NSString).length)
            end = NSMaxRange(token.range)
        }
    }
}
for name in [NSAppearance.Name.aqua, .darkAqua] {
    NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
        let colored = render("```swift\nlet value = \"hello\" // note\n```")
        let color = attribute(.foregroundColor, at: "let", in: colored) as! NSColor
        let expected = SyntaxHighlighter.color(for: .keyword).usingColorSpace(.sRGB)!
        precondition(color.usingColorSpace(.sRGB) == expected)
        precondition((attribute(.font, at: "let", in: colored) as! NSFont).isFixedPitch)
        precondition(links(colored).isEmpty)
        // The actual code background is an opaque dynamic color.
        let background = attribute(.peekdownCodeBackground, at: "let", in: colored) as! NSColor
        func luminance(_ color: NSColor) -> CGFloat {
            let rgb = color.usingColorSpace(.sRGB)!
            func linear(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return linear(rgb.redComponent)*0.2126 + linear(rgb.greenComponent)*0.7152 + linear(rgb.blueComponent)*0.0722
        }
        for kind in [SyntaxHighlighter.Kind.keyword, .comment, .string, .number, .type, .property, .variable] {
            let a = luminance(SyntaxHighlighter.color(for: kind)), b = luminance(background)
            precondition((max(a,b)+0.05)/(min(a,b)+0.05) >= 4.5, "Low syntax contrast for \(kind) in \(name)")
        }
    }
}
for source in ["```unknown\nlet value = 42\n```", "```\nlet value = 42\n```", "    let value = 42", "`let value = 42`"] {
    let plain = render(source)
    precondition((attribute(.foregroundColor, at: "let", in: plain) as! NSColor) == .labelColor)
}
let literal = "let message = \"😀 [link](https://example.org) [^note]\"\n// **literal** <script> & <tag>\n"
let literalRendered = render("~~~swift\n" + literal + "~~~")
precondition(literalRendered.string == literal && links(literalRendered).isEmpty)
precondition((attribute(.font, at: "let", in: MarkdownRenderer.attributedString(from: "```swift\nlet x = 1\n```", fontSize: 22)) as! NSFont).pointSize == 21)
let oversizedCode = "let " + String(repeating: "x", count: SyntaxHighlighter.maxBlockLength)
precondition(SyntaxHighlighter.tokens(in: oversizedCode, language: .swift).isEmpty)
let crowdedCode = String(repeating: "let ", count: SyntaxHighlighter.maxTokens + 1)
precondition(SyntaxHighlighter.tokens(in: crowdedCode, language: .swift).isEmpty)
let budgetBlock = "let " + String(repeating: "x", count: SyntaxHighlighter.maxBlockLength - 4)
let budgetDocument = String(repeating: "```swift\n\(budgetBlock)\n```\n\n", count: 5)
let budgetStart = CFAbsoluteTimeGetCurrent()
let budgetOutput = render(budgetDocument)
let lastLet = (budgetOutput.string as NSString).range(of: "let", options: .backwards)
precondition((budgetOutput.attribute(.foregroundColor, at: lastLet.location, effectiveRange: nil) as! NSColor) == .labelColor)
precondition(CFAbsoluteTimeGetCurrent() - budgetStart < 5, "Bounded syntax rendering took too long")
print("Passed syntax languages, literal preservation, fallbacks, Unicode, contrast, font scaling, and resource bounds")

let denseBlock = String(repeating: "let 1 ", count: 4000)
let denseStart = CFAbsoluteTimeGetCurrent()
let denseOutput = render(String(repeating: "```swift\n\(denseBlock)\n```\n", count: 10))
precondition(denseOutput.string.contains(denseBlock))
let denseTime = CFAbsoluteTimeGetCurrent() - denseStart
precondition(denseTime < 5, "Dense highlighted input exceeded rendering budget")
print("Dense syntax document rendered in \(String(format: "%.3f", denseTime))s")

// Block shading must cover whitespace/wrapped lines rather than individual runs.
let panelDocument = render("```swift\nlet x = 1\n\nlet long = \"a long string that wraps at a narrow width\"\n```\n\n```json\n{}\n```")
var blockRanges: [NSRange] = []
panelDocument.enumerateAttribute(.peekdownCodeBlock, in: NSRange(location: 0, length: panelDocument.length)) { marker, range, _ in
    if marker != nil { blockRanges.append(range) }
}
precondition(blockRanges.count == 2, "Adjacent code blocks need separate panels")
precondition(attribute(.backgroundColor, at: "let", in: panelDocument) == nil, "Code must not use per-character background shading")
let panelParagraph = attribute(.paragraphStyle, at: "let", in: panelDocument) as! NSParagraphStyle
precondition(panelParagraph.headIndent == 12 && panelParagraph.tailIndent == -12)
precondition(panelParagraph.paragraphSpacing == 0)
let panelStorage = NSTextStorage(attributedString: panelDocument)
let panelLayout = CodeBlockLayoutManager()
let panelContainer = NSTextContainer(containerSize: NSSize(width: 280, height: 4000))
panelStorage.addLayoutManager(panelLayout)
panelLayout.addTextContainer(panelContainer)
panelLayout.ensureLayout(for: panelContainer)
let panelGlyphs = panelLayout.glyphRange(forCharacterRange: blockRanges[0], actualCharacterRange: nil)
let firstPanelLine = panelLayout.lineFragmentUsedRect(forGlyphAt: panelGlyphs.location, effectiveRange: nil)
let lastPanelLine = panelLayout.lineFragmentUsedRect(forGlyphAt: NSMaxRange(panelGlyphs)-1, effectiveRange: nil)
let panelImage = NSImage(size: NSSize(width: 300, height: 600))
panelImage.lockFocusFlipped(true)
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: 300, height: 600).fill()
panelLayout.drawBackground(forGlyphRange: panelLayout.glyphRange(for: panelContainer), at: .zero)
panelImage.unlockFocus()
let panelBitmap = NSBitmapImageRep(data: panelImage.tiffRepresentation!)!
let rasterScale = CGFloat(panelBitmap.pixelsWide) / panelImage.size.width
let sampleX = Int(260 * rasterScale)
let sampleY = Int(firstPanelLine.midY * rasterScale)
let panelColor = panelBitmap.colorAt(x: sampleX, y: sampleY)!
precondition(panelColor != panelBitmap.colorAt(x: Int(295 * rasterScale), y: sampleY), "Panel must extend to the available width")
for y in Int(firstPanelLine.midY * rasterScale)...Int(lastPanelLine.midY * rasterScale) {
    precondition(panelBitmap.colorAt(x: sampleX, y: y) == panelColor, "Panel must have continuous color across blank/wrapped lines")
}
precondition(links(panelDocument).isEmpty)
print("Passed continuous code panels, separate blocks, wrapping, blank lines, and padding")
