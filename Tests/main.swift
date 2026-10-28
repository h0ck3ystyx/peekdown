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

struct LinkTest {
    let markdown: String
    let shouldBeClickable: Bool
    let description: String
}

let linkTests: [LinkTest] = [
    // Allowed schemes
    LinkTest(markdown: "[link](http://example.com)", shouldBeClickable: true, description: "http scheme"),
    LinkTest(markdown: "[link](https://example.com)", shouldBeClickable: true, description: "https scheme"),
    LinkTest(markdown: "[link](mailto:test@example.com)", shouldBeClickable: true, description: "mailto scheme"),
    
    // Mixed case allowed schemes
    LinkTest(markdown: "[link](HTTP://example.com)", shouldBeClickable: true, description: "HTTP uppercase"),
    LinkTest(markdown: "[link](HTTPS://example.com)", shouldBeClickable: true, description: "HTTPS uppercase"),
    LinkTest(markdown: "[link](Mailto:test@example.com)", shouldBeClickable: true, description: "Mailto mixed case"),
    LinkTest(markdown: "[link](HtTpS://example.com)", shouldBeClickable: true, description: "HtTpS mixed case"),
    
    // Schemes with leading whitespace
    LinkTest(markdown: "[link]( http://example.com)", shouldBeClickable: true, description: "http with leading space"),
    LinkTest(markdown: "[link](\thttps://example.com)", shouldBeClickable: true, description: "https with leading tab"),
    LinkTest(markdown: "[link]( \t mailto:test@example.com)", shouldBeClickable: true, description: "mailto with leading whitespace"),
    
    // Disallowed schemes
    LinkTest(markdown: "[link](javascript:alert(1))", shouldBeClickable: false, description: "javascript scheme"),
    LinkTest(markdown: "[link](file:///etc/passwd)", shouldBeClickable: false, description: "file scheme"),
    LinkTest(markdown: "[link](data:text/html,<script>alert(1)</script>)", shouldBeClickable: false, description: "data scheme"),
    LinkTest(markdown: "[link](vbscript:msgbox)", shouldBeClickable: false, description: "vbscript scheme"),
    LinkTest(markdown: "[link](ftp://example.com)", shouldBeClickable: false, description: "ftp scheme"),
    LinkTest(markdown: "[link](custom://action)", shouldBeClickable: false, description: "custom scheme"),
    
    // Mixed case disallowed schemes
    LinkTest(markdown: "[link](JavaScript:alert(1))", shouldBeClickable: false, description: "JavaScript mixed case"),
    LinkTest(markdown: "[link](FILE:///etc/passwd)", shouldBeClickable: false, description: "FILE uppercase"),
    LinkTest(markdown: "[link](DaTa:text/html)", shouldBeClickable: false, description: "DaTa mixed case"),
    
    // Relative URLs (should be allowed - no scheme)
    LinkTest(markdown: "[link](./page.html)", shouldBeClickable: true, description: "relative path with ./"),
    LinkTest(markdown: "[link](../page.html)", shouldBeClickable: true, description: "relative path with ../"),
    LinkTest(markdown: "[link](/absolute/path)", shouldBeClickable: true, description: "absolute path no scheme"),
    LinkTest(markdown: "[link](page.html)", shouldBeClickable: true, description: "relative file name"),
]

for test in linkTests {
    let result = MarkdownRenderer.attributedString(from: test.markdown)
    let hasLink = result.attribute(.link, at: 0, effectiveRange: nil) != nil
    precondition(hasLink == test.shouldBeClickable,
                 "Link test failed for \(test.description): expected clickable=\(test.shouldBeClickable), got \(hasLink)")
}

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

// MARK: - File size limit tests

func createTempMarkdown(size: Int) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).md")
    let content = String(repeating: "# Test\n", count: size / 7)
    try? content.write(to: url, atomically: true, encoding: .utf8)
    return url
}

// Test small file renders successfully
let smallFile = createTempMarkdown(size: 1000)
var smallFileRendered = false
controller.preparePreviewOfFile(at: smallFile) { error in
    smallFileRendered = error == nil
}
precondition(smallFileRendered, "Small file should render successfully")
try? FileManager.default.removeItem(at: smallFile)

// Test file larger than limit shows fallback
let largeFile = createTempMarkdown(size: RenderingConstants.maxFileSize + 1000)
var largeFileHandled = false
controller.preparePreviewOfFile(at: largeFile) { error in
    largeFileHandled = error == nil  // Should succeed but show fallback message
}
precondition(largeFileHandled, "Large file should be handled gracefully")
try? FileManager.default.removeItem(at: largeFile)

// MARK: - Summary

print("✅ Passed \(frontMatterCases.count) front-matter cases")
print("✅ Passed renderer integration and non-Markdown rejection")
print("✅ Passed \(linkTests.count) link scheme validation tests")
print("✅ Passed table separator ReDoS protection test (completed in \(String(format: "%.3f", tablePerfTime))s)")
print("✅ Passed file size limit tests")
print("All tests passed!")
