# Experimental native previews

Peekdown v1.1.0 includes appearance preferences and experimental Mermaid, display
math, and static MDX previews. Open Peekdown to adjust text size (80–160%), paragraph density,
and code spacing (0–6 points). Enable the two experimental switches for diagrams
and equations, then close and reopen Quick Look. Both switches default to off.

For a combined demo, select `Peekdown/Resources/Experimental-preview.md` in
Finder and press Space. The app's demo shortcut currently has a known reveal
issue; open the source demo directly. Use `Tests/Fixtures/experimental.mdx` for
static MDX and `Tests/Fixtures/sample.yaml` for YAML.

- Mermaid: small `flowchart`, `graph`, and `sequenceDiagram` fences. Unsupported diagrams stay visible as source. Styling directives, HTML labels, and interactions are excluded.
- Math: display expressions on separate lines between `$$` or `\[` and `\]`. Inline math is not enabled. Unsupported expressions stay visible as source.
- MDX: Markdown paragraphs render normally; paragraphs containing imports, exports, JSX, or expressions remain literal source. Components and JavaScript never execute. This is a conservative static view, not a full MDX parser.
- Rendering stays native and offline. At most four diagram/math blocks are attempted per preview; input and image sizes are bounded.

Run `./scripts/test.sh` for native regression checks. `./build.sh` creates a universal development app. The first build resolves and compiles pinned Swift packages and requires network access; previewing documents does not. Dependency licenses and source references are in `ThirdParty/`.

The prototype uses a shared app-group preference suite for the host and preview extension. Verify preference changes in Finder on a signed installation before release. Existing editor file associations should remain unchanged.

## Local Finder verification (2026-11-01)

Signed experimental build 16 was exercised in Finder Quick Look:

- Host Mermaid/equation toggles enabled rendering in the preview extension.
- Flowchart and sequence labels rendered in the correct positions.
- Both sample equations rendered with packaged fonts.
- Changing text size to 130% changed the reopened preview; restored to 100% afterward.
- Static MDX rendered ordinary Markdown and retained imports, JSX, and expressions as source.
- Markdown retained **Open with Cursor**; MDX retained **Open with TextEdit**.

The two experimental switches were left enabled for local testing. The host's **Show experiment demo in Finder** shortcut did not reveal the bundled file in this session and needs follow-up. Open `Peekdown/Resources/Experimental-preview.md` in Finder directly for now.

## Syntax examples

Mermaid uses a fenced block:

````markdown
```mermaid
flowchart LR
    A[Read Markdown] --> B[Native preview]
```
````

Display math requires delimiters on their own lines:

```text
$$
x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}
$$
```

Mermaid inputs are capped at 4,096 UTF-16 units and 48 nonempty lines. Math
inputs are capped at 1,024 UTF-16 units and 16 brace levels, with at most 32 lines
between display delimiters. Up to four diagram/equation blocks are attempted per
document, including failed attempts. Invalid, unsupported, or over-budget blocks
stay readable as source. Generated images fit the available preview width.

This does not support inline math, arbitrary Mermaid diagram families, HTML
labels, Mermaid interactions, or executing MDX imports/components. MDX source
preservation is conservative: a paragraph containing angle brackets or braces
may be displayed entirely as code, even when it also contains ordinary prose.
