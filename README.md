# MarkdownPreview

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

## Requirements

- macOS 12.0+
- [Xcode](https://apps.apple.com/app/xcode/id497799835) (full Xcode, not just Command Line Tools) — the preview extension needs a real code-signing identity
- An Apple ID signed into Xcode with a (free) **Personal Team**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

> **Why a real identity?** On macOS 13+, Quick Look *preview* extensions are discovered by ExtensionKit, which does not launch ad-hoc-signed preview extensions (symptom: raw text, or a `key cannot be nil` crash). *Thumbnail* extensions work ad-hoc via a separate daemon. The free Personal Team is sufficient.

## Build & install

### 1. Configure signing

Edit `DEVELOPMENT_TEAM` in `project.yml` to your own team ID. Find it with:

```bash
defaults read com.apple.dt.Xcode | grep -A4 IDEProvisioningTeamByIdentifier
```

### 2. Build (Xcode)

```bash
cd MarkdownPreview
xcodegen generate
xcodebuild -project MarkdownPreview.xcodeproj \
  -scheme MarkdownPreview -configuration Release \
  -derivedDataPath ./build build
```

The first build generates the `Apple Development` certificate and provisioning profiles automatically.

### 3. Install

```bash
ditto build/Build/Products/Release/MarkdownPreview.app /Applications/MarkdownPreview.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R /Applications/MarkdownPreview.app
pluginkit -a /Applications/MarkdownPreview.app/Contents/PlugIns/PreviewExtension.appex
pluginkit -a /Applications/MarkdownPreview.app/Contents/PlugIns/ThumbnailExtension.appex
killall quicklookd; qlmanage -r; qlmanage -r cache
open /Applications/MarkdownPreview.app
```

Then select any `.md` file in Finder and press **Space**.

### Command-Line-Tools-only fallback (`build.sh`)

`build.sh` compiles everything with `swiftc` and ad-hoc-signs it. It produces a working **thumbnail** extension, but the preview extension will not register under ad-hoc signing — use the Xcode path above for previews.

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
| `MarkdownPreview` | macOS app | Registers the markdown UTI; hosts the extensions |
| `PreviewExtension` | Quick Look preview (`.appex`) | Renders the document on Space |
| `ThumbnailExtension` | Quick Look thumbnail (`.appex`) | Draws the Finder thumbnail card |

`MarkdownRenderer.swift` is a self-contained, dependency-free markdown → `NSAttributedString` renderer (block parser + inline tokenizer). It deliberately avoids `WKWebView` (its WebContent XPC subprocess is unreliable inside the sandbox) and data-based `QLPreviewReply` (whose WebKit context does not execute JavaScript).

## Project layout

```
project.yml              # XcodeGen spec — source of truth for the .xcodeproj
build.sh                 # CLT-only build fallback (ad-hoc signed)
MarkdownPreview/         # host app (SwiftUI)
PreviewExtension/        # Quick Look preview extension + MarkdownRenderer
ThumbnailExtension/      # Quick Look thumbnail extension
Packaging/               # hand-written plists used by build.sh
```

## Notes & caveats

- **Free Personal Team certificates expire after ~7 days.** When previews stop working, rebuild and re-sign — Xcode re-issues the certificate automatically.
- `qlmanage -p` (the CLI preview tool) crashes on macOS 26/27 for extension-based previews (`key cannot be nil`); it is a legacy-tool limitation, not a bug here. Verify previews via Finder Space; use `qlmanage -t` for thumbnails.
- The table renderer caps its width to the panel and word-wraps cells; very long unbreakable tokens (e.g. long filenames) may split mid-token.
