# Peekdown

[Website & demo](https://h0ck3ystyx.github.io/peekdown/) · [Download the latest release](https://github.com/h0ck3ystyx/peekdown/releases/latest)

A native macOS Quick Look extension that renders Markdown (`.md`, `.markdown`, `.mdown`, `.mkd`, `.mkdn`) as formatted documents when you press **Space** in Finder — headings, lists, tables, code, and more — and syntax-highlights standalone YAML (`.yaml`, `.yml`). Markdown files also get a styled thumbnail in the Finder preview pane.

Markdown is parsed to an `NSAttributedString` in Swift and drawn with AppKit. No WebKit, no JavaScript, no HTML importer — so it works inside the Quick Look sandbox.

## Release status

The published installer, ZIP, and Homebrew cask currently provide **v1.0.4**.
The appearance settings, experimental Mermaid/math, static MDX, and standalone
YAML described below are in the development source for the next release; they
are not included in those downloads yet. YAML is being integrated in
[PR #24](https://github.com/h0ck3ystyx/peekdown/pull/24).

## Features

- **Quick Look preview** — select a `.md` file and press Space for a rendered document.
- **YAML preview (next release)** — select a `.yaml` or `.yml` file and press Space for a syntax-colored code panel. Oversized or invalid YAML stays plain monospaced text. See [YAML previews](docs/yaml-support.md).
- **Appearance preferences (next release)** — open Peekdown to adjust text size (80–160%), compact paragraph spacing, and code line spacing. Reopen Quick Look to apply changes.
- **Experimental Mermaid (next release, off by default)** — native flowcharts and sequence diagrams in `mermaid` fences. Unsupported input remains source.
- **Experimental display math (next release, off by default)** — native equations between standalone `$$` or `\[` / `\]` delimiter lines. Inline math is not enabled.
- **Static MDX (next release)** — `.mdx` previews render ordinary Markdown; imports, JSX, and expressions remain literal source and never execute. This is not full MDX component rendering.
- **Finder thumbnails** — a styled card with the first heading and a text snippet for Markdown files.
- Renders CommonMark-ish Markdown natively:
  - ATX and setext headings
  - bold, italic, strikethrough, inline code
  - fenced and indented code blocks
  - language-aware fenced-code colors for Swift, shell, JSON, YAML, Python, JavaScript, and TypeScript (available in v1.0.4)
  - ordered, unordered, and nested lists
  - GFM task lists (`- [x]` / `- [ ]` → ☑ / ☐)
  - tables (box-drawn, width-capped and word-wrapped)
  - links, images (alt text), blockquotes, horizontal rules
  - URL/email recognition with a Copy link fallback, numbered footnotes, and GitHub-style alerts (available in v1.0.3)
  - YAML front-matter stripping
- Light and dark mode (system label colors).
- The host app imports the `net.daringfireball.markdown` UTI so Finder routes `.md` files to this extension.
- Standalone YAML uses the system `public.yaml` type (`.yaml` and `.yml`). The host app declares that type with document role and handler rank `None`, so Peekdown does not become the default editor.

See [native Markdown support](docs/markdown-support.md) for syntax examples and
limitations. See [experimental previews and settings](docs/experimental-preview.md) for examples and limits. Quick Look
may block opening external links; copying a recognized destination is supported.
The host app registers Markdown types for previews without claiming to be a
document editor or viewer.

## Installation

### Homebrew (recommended)

```bash
brew install --cask h0ck3ystyx/tap/peekdown
```

### Manual installation

Download the latest release from the [releases page](https://github.com/h0ck3ystyx/peekdown/releases/latest).

- **Installer package**: Download and run `Peekdown-VERSION.pkg`
- **ZIP archive**: Download `Peekdown-VERSION.zip`, extract, and move `Peekdown.app` to `~/Applications`

After installation, launch `Peekdown.app` once, then select a Markdown file in Finder
and press **Space**. Development builds also accept `.yaml`, `.yml`, and `.mdx`.

## Distribution releases

Signed and notarized releases are built automatically via GitHub Actions when a `v*`
tag is pushed. See [RELEASE.md](RELEASE.md) for release automation setup and local
release instructions. The release build supports Intel and Apple Silicon.
Development signing and ad-hoc builds below are for local use.

The installer `.pkg` offers **Install for me only** (`~/Applications`, no admin password)
and **Install for all users of this computer** (`/Applications`, administrator
authorization). Use **Change Install Location…** if Installer skips the
destination screen.

Peekdown was previously named MarkdownPreview. After installing Peekdown, remove
the old `MarkdownPreview.app` copy to avoid duplicate extension registrations.
The bundle identifiers retain `com.markdownpreview` for signing continuity.

## Requirements

- macOS 12.0+
- [Xcode](https://apps.apple.com/app/xcode/id497799835) (full Xcode, not just Command Line Tools) — the preview extension needs a real code-signing identity
- An Apple ID signed into Xcode with a (free) **Personal Team**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

> **Why a real identity?** On macOS 13+, Quick Look *preview* extensions are discovered by ExtensionKit, which does not launch ad-hoc-signed preview extensions (symptom: raw text, or a `key cannot be nil` crash). *Thumbnail* extensions work ad-hoc via a separate daemon. The free Personal Team is sufficient.

## Build & install

### 1. Configure signing

Set your development team when building (or edit `DEVELOPMENT_TEAM` in
`project.yml`). Find your team ID with:

```bash
defaults read com.apple.dt.Xcode | grep -A4 IDEProvisioningTeamByIdentifier
```

### 2. Build (Xcode)

```bash
cd peekdown
xcodegen generate
xcodebuild -project Peekdown.xcodeproj \
  -scheme Peekdown -configuration Release \
  -derivedDataPath ./build DEVELOPMENT_TEAM=YOUR_TEAM_ID -allowProvisioningUpdates build
```

The build resolves pinned Swift dependencies. Signed preview settings use a
team-prefixed App Group; developers using another team must update the group
identifier in `Shared/PreviewSettings.swift` and both app/preview entitlements
through `project.yml`. Configure signing and provisioning for that group.

### 3. Install

```bash
ditto build/Build/Products/Release/Peekdown.app /Applications/Peekdown.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R /Applications/Peekdown.app
pluginkit -a /Applications/Peekdown.app/Contents/PlugIns/PreviewExtension.appex
pluginkit -a /Applications/Peekdown.app/Contents/PlugIns/ThumbnailExtension.appex
killall quicklookd; qlmanage -r; qlmanage -r cache
open /Applications/Peekdown.app
```

Then select a `.md` or `.yaml` file in Finder and press **Space**. For a command-line check after the extension is registered:

```bash
qlmanage -p file.yaml
qlmanage -p file.yml
```

On macOS 26/27, `qlmanage -p` can crash for extension-based previews. Use Finder Space there, and `qlmanage -t` for Markdown thumbnails.

### Command-Line-Tools-only fallback (`build.sh`)

`./build.sh` compiles universal Intel/Apple Silicon binaries with `swiftc` and ad-hoc-signs them at `build/local/Peekdown.app`. Ad-hoc builds are for compilation and local checks; use development signing for Finder testing or `./release.sh` for distribution. The release pipeline uses the same compiler path with Developer ID signing, so it does not require XcodeGen.

## How it works

```
Finder (Space)
  └─ Quick Look → PreviewExtension.appex
       └─ PreviewViewController (QLPreviewingController)
            ├─ Markdown → MarkdownRenderer → NSAttributedString
            └─ YAML → YAMLPreview (syntax colors, or plain text)
                 └─ NSTextView inside NSScrollView
```

Three targets live inside a single app:

| Target | Type | Purpose |
|---|---|---|
| `Peekdown` | macOS app | Registers preview types; hosts settings and extensions |
| `PreviewExtension` | Quick Look preview (`.appex`) | Renders Markdown, static MDX, and YAML on Space |
| `ThumbnailExtension` | Quick Look thumbnail (`.appex`) | Draws the Finder thumbnail card for Markdown |

`MarkdownRenderer.swift` parses Markdown into native attributed text. Optional diagram and equation images use pinned BeautifulMermaidSwift and SwiftMath dependencies; see [dependency notices](ThirdParty/README.md). It deliberately avoids `WKWebView` (its WebContent XPC subprocess is unreliable inside the sandbox) and data-based `QLPreviewReply` (whose WebKit context does not execute JavaScript). `YAMLPreview.swift` reuses that renderer's code-panel metrics and the YAML lexer, after a structural check. Invalid or oversized YAML is the same panel with plain monospaced text.

## Project layout

```
project.yml              # XcodeGen spec — source of truth for the .xcodeproj
build.sh                 # universal build (ad-hoc by default)
release.sh               # Developer ID signing, notarization, signed .pkg
RELEASE.md               # certificates and release instructions
Shared/                  # front matter, preview settings, static MDX
NativeSupport/           # native Mermaid/math bridge
Vendor/                  # SwiftMath with extension resource lookup patch
ThirdParty/              # dependency and font license notices
Tests/                   # parser and renderer regressions
scripts/                 # test runner and installer packaging
Peekdown/         # host app (SwiftUI)
PreviewExtension/        # Quick Look preview extension, Markdown and YAML renderers
ThumbnailExtension/      # Quick Look thumbnail extension
Packaging/               # hand-written plists used by build.sh
```

## Notes & caveats

- Development provisioning can expire; rebuild through Xcode if a local development installation stops working. Use Developer ID signing and notarization for distribution.
- `qlmanage -p` (the CLI preview tool) crashes on macOS 26/27 for extension-based previews (`key cannot be nil`); it is a legacy-tool limitation, not a bug here. Verify previews via Finder Space; use `qlmanage -t` for thumbnails.
- The table renderer caps its width to the panel and word-wraps cells; very long unbreakable tokens (e.g. long filenames) may split mid-token.

## License

Peekdown’s own source is available under the [MIT License](LICENSE). Bundled
dependencies and fonts retain their respective licenses; see
[third-party notices](ThirdParty/README.md), including ElkSwift’s EPL-2.0 license.

### Quick Look’s “Open with” button

This button uses the document’s macOS file association; it does not select the
Quick Look extension. Older Peekdown builds declared themselves an Owner-rank
Markdown viewer and could appear there instead of your editor. Current source
uses document role/rank `None` while retaining Markdown type declarations.

To restore Xcode (or another editor), select a `.md` file in Finder, choose
**Get Info → Open with**, select the editor, then choose **Change All…** if you
want it to be the default for that file type. Installing a corrected build does
not explicitly reset your existing editor preferences.
