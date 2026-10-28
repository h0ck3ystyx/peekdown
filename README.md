# Peekdown

[Website & demo](https://h0ck3ystyx.github.io/peekdown/) · [Download the latest release](https://github.com/h0ck3ystyx/peekdown/releases/latest)

A native macOS Quick Look extension that renders Markdown (`.md`, `.markdown`, `.mdown`, `.mkd`, `.mkdn`) as formatted documents when you press **Space** in Finder — headings, lists, tables, code, and more — plus a styled thumbnail for the Finder preview pane.

Markdown is parsed to an `NSAttributedString` in Swift and drawn with AppKit. No WebKit, no JavaScript, no HTML importer — so it works inside the Quick Look sandbox.

## Features

- **Quick Look preview** — select a `.md` file and press Space for a rendered document.
- **Finder thumbnails** — a styled card with the first heading and a text snippet.
- Renders CommonMark-ish Markdown natively:
  - ATX and setext headings
  - bold, italic, strikethrough, inline code
  - fenced and indented code blocks
  - ordered, unordered, and nested lists
  - GFM task lists (`- [x]` / `- [ ]` → ☑ / ☐)
  - tables (box-drawn, width-capped and word-wrapped)
  - links, images (alt text), blockquotes, horizontal rules
  - YAML front-matter stripping
- Light and dark mode (system label colors).
- The host app declares the `net.daringfireball.markdown` UTI so Finder routes `.md` files to this extension.

## Distribution releases

Use [RELEASE.md](RELEASE.md) for Developer ID certificate setup and the signed,
notarized ZIP and `.pkg` pipeline. The release build supports Intel and Apple Silicon.
Development signing and ad-hoc builds below are for local use.

The `.pkg` offers **Install for me only** (`~/Applications`, no admin password)
and **Install for all users of this computer** (`/Applications`, administrator
authorization). Use **Change Install Location…** if Installer skips the
destination screen.

For installation without administrator access, extract the release ZIP, move
`Peekdown.app` into `~/Applications` (create the folder if needed), and launch it
once. Select a Markdown file in Finder and press Space. You may need to enable
the Quick Look extension in System Settings.

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

The first build generates the `Apple Development` certificate and provisioning profiles automatically.

### 3. Install

```bash
ditto build/Build/Products/Release/Peekdown.app /Applications/Peekdown.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R /Applications/Peekdown.app
pluginkit -a /Applications/Peekdown.app/Contents/PlugIns/PreviewExtension.appex
pluginkit -a /Applications/Peekdown.app/Contents/PlugIns/ThumbnailExtension.appex
killall quicklookd; qlmanage -r; qlmanage -r cache
open /Applications/Peekdown.app
```

Then select any `.md` file in Finder and press **Space**.

### Command-Line-Tools-only fallback (`build.sh`)

`./build.sh` compiles universal Intel/Apple Silicon binaries with `swiftc` and ad-hoc-signs them at `build/local/Peekdown.app`. Ad-hoc builds are for compilation and local checks; use development signing for Finder testing or `./release.sh` for distribution. The release pipeline uses the same compiler path with Developer ID signing, so it does not require XcodeGen.

## How it works

```
Finder (Space)
  └─ Quick Look → PreviewExtension.appex
       └─ PreviewViewController (QLPreviewingController)
            └─ MarkdownRenderer: markdown → NSAttributedString
                 └─ NSTextView inside NSScrollView
```

Three targets live inside a single app:

| Target | Type | Purpose |
|---|---|---|
| `Peekdown` | macOS app | Registers the markdown UTI; hosts the extensions |
| `PreviewExtension` | Quick Look preview (`.appex`) | Renders the document on Space |
| `ThumbnailExtension` | Quick Look thumbnail (`.appex`) | Draws the Finder thumbnail card |

`MarkdownRenderer.swift` is a self-contained, dependency-free markdown → `NSAttributedString` renderer (block parser + inline tokenizer). It deliberately avoids `WKWebView` (its WebContent XPC subprocess is unreliable inside the sandbox) and data-based `QLPreviewReply` (whose WebKit context does not execute JavaScript).

## Project layout

```
project.yml              # XcodeGen spec — source of truth for the .xcodeproj
build.sh                 # universal build (ad-hoc by default)
release.sh               # Developer ID signing, notarization, signed .pkg
RELEASE.md               # certificates and release instructions
Shared/                  # shared front-matter parser
Tests/                   # parser and renderer regressions
scripts/                 # test runner and installer packaging
Peekdown/         # host app (SwiftUI)
PreviewExtension/        # Quick Look preview extension + MarkdownRenderer
ThumbnailExtension/      # Quick Look thumbnail extension
Packaging/               # hand-written plists used by build.sh
```

## Notes & caveats

- Development provisioning can expire; rebuild through Xcode if a local development installation stops working. Use Developer ID signing and notarization for distribution.
- `qlmanage -p` (the CLI preview tool) crashes on macOS 26/27 for extension-based previews (`key cannot be nil`); it is a legacy-tool limitation, not a bug here. Verify previews via Finder Space; use `qlmanage -t` for thumbnails.
- The table renderer caps its width to the panel and word-wraps cells; very long unbreakable tokens (e.g. long filenames) may split mid-token.

## License

Peekdown is available under the [MIT License](LICENSE).
