# YAML previews

Press Space on a `.yaml` or `.yml` file in Finder to preview it. The preview
uses the same monospaced code panel, padding, and light/dark syntax colors as a
fenced YAML block inside a Markdown document. Finder thumbnails stay
Markdown-only.

## File types

The preview extension lists `public.yaml` in `QLSupportedContentTypes`. macOS 12
and later assigns that system type to `.yaml` and `.yml`. The host app declares
the same type with document role `None` and handler rank `None`. Peekdown does
not become the default app for YAML, and it does not redeclare `public.yaml`.

## What you see

Valid YAML within the highlighting budget is colored with the existing offline
lexer: keys, comments, quoted strings, numbers, and booleans (`true`, `false`,
`null`, `yes`, `no`, and the other YAML literals the lexer already knows).
Colors follow the system light and dark appearance. The source text is shown
as-is. Nothing in the file is executed, and tags are not resolved.

These stay plain monospaced text in the same panel:

- YAML that fails the structural check (an unclosed quote, a tab used as
  indentation, an undefined alias, or another malformed document)
- Documents larger than 65,536 UTF-16 units, or with more colored tokens than
  the highlighter allows
- Files that are not valid UTF-8

The structural check covers common YAML: mappings, sequences, flow collections,
block scalars, anchors, aliases, directives, and multiple documents. Some
unusual but valid documents are shown as plain text instead of colored text.
The full source is still displayed.

Files larger than 10 MB are not loaded in full. The preview shows a plain-text
prefix and a short note that the rest was omitted.

## Checks

`./scripts/test.sh` covers the structural cases, highlighting, plain-text
fallbacks, and the extension gate for `.yaml` / `.yml`.

After a signed build is installed and Quick Look has been reset:

```bash
qlmanage -p file.yaml
qlmanage -p file.yml
```

Then press Space on the same files in Finder, in both Light and Dark appearance.
Also try an invalid file (for example an unclosed quote) and confirm the text
is still readable without syntax colors. On macOS 26/27, `qlmanage -p` can
crash for extension-based previews; Finder Space is the check to use there.

## Integration validation

The local integration with native diagram/math and static MDX support was checked
on 2026-11-01 using signed experimental build 17. Native tests include 205 YAML
structure cases plus preferences, nesting limits, missing-file reads, and MDX
routing. Both universal CLI and Xcode Release builds passed. Finder confirmed
colored `.yaml`, plain fallback for malformed `.yml`, and preserved Markdown/MDX
previews and editor associations. Light/dark YAML rendering was checked offscreen.

The structural parser stops after 128 nested parser nodes and falls back to plain
text. YAML panels honor the host's text-size and code-spacing preferences.
