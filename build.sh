#!/bin/bash
# Build MarkdownPreview.app (host + Quick Look preview/thumbnail extensions)
# using only the Command Line Tools (no full Xcode required).
set -euo pipefail
cd "$(dirname "$0")"

SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="arm64-apple-macos12.0"
BUILD="build"
DEST="$BUILD/MarkdownPreview.app"

rm -rf "$BUILD"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources" "$DEST/Contents/PlugIns"

echo "==> Compiling PreviewExtension.appex"
PE="$DEST/Contents/PlugIns/PreviewExtension.appex"
mkdir -p "$PE/Contents/MacOS"
swiftc -emit-executable -module-name PreviewExtension \
  -o "$PE/Contents/MacOS/PreviewExtension" \
  -sdk "$SDK" -target "$TARGET" \
  -framework QuickLookUI -framework AppKit \
  -Xlinker -e -Xlinker _NSExtensionMain \
  PreviewExtension/MarkdownRenderer.swift PreviewExtension/PreviewViewController.swift
cp Packaging/PreviewExt-Info.plist "$PE/Contents/Info.plist"

echo "==> Compiling ThumbnailExtension.appex"
TE="$DEST/Contents/PlugIns/ThumbnailExtension.appex"
mkdir -p "$TE/Contents/MacOS"
swiftc -emit-executable -module-name ThumbnailExtension \
  -o "$TE/Contents/MacOS/ThumbnailExtension" \
  -sdk "$SDK" -target "$TARGET" \
  -framework QuickLookThumbnailing -framework AppKit \
  -Xlinker -e -Xlinker _NSExtensionMain \
  ThumbnailExtension/ThumbnailProvider.swift
cp Packaging/ThumbExt-Info.plist "$TE/Contents/Info.plist"

echo "==> Compiling host app"
swiftc -emit-executable -module-name MarkdownPreview \
  -o "$DEST/Contents/MacOS/MarkdownPreview" \
  -sdk "$SDK" -target "$TARGET" \
  -framework SwiftUI \
  MarkdownPreview/MarkdownPreviewApp.swift MarkdownPreview/ContentView.swift
cp Packaging/App-Info.plist "$DEST/Contents/Info.plist"

echo "==> Signing (ad-hoc, inner -> outer)"
codesign --force --sign - --entitlements PreviewExtension/PreviewExtension.entitlements "$PE"
codesign --force --sign - --entitlements ThumbnailExtension/ThumbnailExtension.entitlements "$TE"
codesign --force --sign - --entitlements MarkdownPreview/MarkdownPreview.entitlements "$DEST"

echo "==> Verifying signatures"
codesign --verify --verbose=2 "$PE" >/dev/null 2>&1 && echo "  PreviewExtension.appex: valid"
codesign --verify --verbose=2 "$TE" >/dev/null 2>&1 && echo "  ThumbnailExtension.appex: valid"
codesign --verify --verbose=2 "$DEST" >/dev/null 2>&1 && echo "  MarkdownPreview.app: valid"

echo "==> Build complete: $DEST"
