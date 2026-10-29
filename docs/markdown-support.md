# Native Markdown support

This describes the native renderer shipped in Peekdown v1.0.3, including
autolinks, footnotes, and GitHub-style alerts.
Peekdown uses native AppKit attributed text, not GitHub's HTML renderer. It
supports a useful Markdown subset rather than claiming full CommonMark/GFM
conformance or identical visual output. The website playground is a separate
browser renderer.

## Autolinks

HTTP and HTTPS URLs, `www.` addresses, and ordinary ASCII email addresses become
link-styled in prose, headings, lists, blockquotes, and table cells:

```markdown
Visit https://example.org/docs, www.example.org, or <https://example.org/a_(b)>.
Email reader@example.org or <reader@example.org>.
```

### Link behavior requirements

- Recognize web and email destinations and preserve their link styling.
- On an explicit click, request opening through the Quick Look host and the
  public workspace API. External browser/Mail launching is best-effort, not a
  required or guaranteed feature: the tested Finder host denies both routes.
- When opening is denied, show a visible **Copy link** action. Copy the complete
  URL, including `mailto:` for email links, and confirm success without a beep.
- Do not automatically fetch URLs, widen sandbox entitlements, or add a helper
  process to satisfy link launching.
- Accept HTTP, HTTPS, and mailto links for click handling; consume unsupported
  schemes without trying to launch them.
- Footnote numbers remain readable reference markers, without navigation links.

`www.` addresses use `http://`; emails use `mailto:`. Sentence punctuation and
unmatched trailing closing brackets are excluded from bare links. Balanced
parentheses in URLs are preserved. Explicit `[label](destination)` links retain
their destination, including labels that look like URLs. Code spans, fenced
blocks, indented code, image alt text, and escaped delimiters remain literal.
This does not implement every URI scheme, internationalized email address,
HTML link, GitHub mention, or GFM autolink edge case.

## Footnotes

Use a reference and a top-level definition, anywhere in the document:

```markdown
A short explanation[^details], then another reference[^details].

[^details]: The full explanation with **formatting** and https://example.org.
    Continuation lines use four spaces or a tab.

    Another indented paragraph is part of the same note.
```

Notes are numbered by first reference and collected under **Footnotes** at the
end. Repeated references use the same number. Undefined references remain as
`[^label]`; unused definitions are hidden. The first definition of a duplicate
label wins. Labels are case-sensitive and cannot contain whitespace or brackets.
Definitions may have up to three leading spaces and are extracted only from the
top level, outside code blocks. Definitions nested in lists or quotes are not
supported. Paragraphs, inline formatting, lists, and blockquotes can appear in
indented continuation lines.

References appear as superscript `[n]` in prose and fixed-width `[n]` in tables.
They are readable markers, not clickable navigation anchors. Circular references
are rendered once per definition without recursive expansion.

## GitHub-style alerts

Start a quote with one of the five uppercase markers on a line of its own:

```markdown
> [!NOTE]
> Useful information with **emphasis** and a link: https://example.org.
>
> A second paragraph.

> [!WARNING]
> Something that needs attention.
```

Supported markers are `[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, and
`[!CAUTION]`. Each gets a text label, a distinct system color, and a lightly tinted
background that follows light/dark appearance. An unknown marker remains an
ordinary blockquote. A marker inside code is literal. Separate adjacent alerts
with an unquoted blank line. Native spacing, symbols, and colors intentionally
differ from GitHub's rendering.

## Regression checks

Run `./scripts/test.sh`. The suite checks the attributed text (link destinations,
reference numbering and styling, nested formatting, and callout colors in both
appearances), plus malformed syntax and large documents. A combined sample is
in [Tests/Fixtures/issue-1.md](../Tests/Fixtures/issue-1.md).
