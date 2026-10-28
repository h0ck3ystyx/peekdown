import AppKit
let cases: [(String, String)] = [
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
for (input, expected) in cases {
    precondition(MarkdownText.stripFrontMatter(input) == expected, "Front matter mismatch: \(input.debugDescription)")
    _ = MarkdownRenderer.attributedString(from: input)
}
let rendered = MarkdownRenderer.attributedString(from: "---\ntitle: hidden\n---\n# Visible")
precondition(rendered.string.contains("Visible") && !rendered.string.contains("hidden"))
var rejected = false
let controller = PreviewViewController()
controller.preparePreviewOfFile(at: URL(fileURLWithPath: "/tmp/unrelated.txt")) { error in
    rejected = error != nil
}
precondition(rejected, "Non-Markdown request must not return a blank successful preview")
print("Passed \(cases.count) front-matter cases, renderer integration, and non-Markdown rejection")
