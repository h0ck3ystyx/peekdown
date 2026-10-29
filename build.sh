#!/bin/bash
# Universal macOS build. Ad-hoc by default; release.sh supplies Developer ID.
set -euo pipefail
cd "$(dirname "$0")"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
BUILD="build/local"
DEST="$BUILD/Peekdown.app"
IDENTITY="${APPLICATION_IDENTITY:--}"
source scripts/version.sh
rm -rf "$BUILD"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources" "$DEST/Contents/PlugIns"
compile() {
    local name="$1" output="$2"
    shift 2
    local arch
    for arch in arm64 x86_64; do
        xcrun swiftc -O -emit-executable -module-name "$name" \
          -sdk "$SDK" -target "$arch-apple-macos12.0" \
          -o "$BUILD/$name-$arch" "$@"
    done
    xcrun lipo -create "$BUILD/$name-arm64" "$BUILD/$name-x86_64" -output "$output"
    xcrun lipo "$output" -verify_arch arm64 x86_64
}
PE="$DEST/Contents/PlugIns/PreviewExtension.appex"
TE="$DEST/Contents/PlugIns/ThumbnailExtension.appex"
mkdir -p "$PE/Contents/MacOS" "$TE/Contents/MacOS"
echo "==> Compiling universal extensions and app"
compile PreviewExtension "$PE/Contents/MacOS/PreviewExtension" \
  -framework QuickLookUI -framework AppKit -application-extension \
  -Xlinker -e -Xlinker _NSExtensionMain \
  Shared/MarkdownText.swift Shared/RenderingConstants.swift PreviewExtension/SyntaxHighlighter.swift PreviewExtension/MarkdownRenderer.swift PreviewExtension/PreviewViewController.swift
compile ThumbnailExtension "$TE/Contents/MacOS/ThumbnailExtension" \
  -framework QuickLookThumbnailing -framework AppKit -application-extension \
  -Xlinker -e -Xlinker _NSExtensionMain \
  Shared/MarkdownText.swift Shared/RenderingConstants.swift ThumbnailExtension/ThumbnailProvider.swift
compile Peekdown "$DEST/Contents/MacOS/Peekdown" \
  -framework SwiftUI Peekdown/PeekdownApp.swift Peekdown/ContentView.swift
cp Packaging/PreviewExt-Info.plist "$PE/Contents/Info.plist"
cp Packaging/ThumbExt-Info.plist "$TE/Contents/Info.plist"
cp Packaging/App-Info.plist "$DEST/Contents/Info.plist"
cp LICENSE "$DEST/Contents/Resources/LICENSE"
cp Peekdown/Resources/Peekdown.icns "$DEST/Contents/Resources/Peekdown.icns"
for bundle in "$PE" "$TE" "$DEST"; do
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$bundle/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$bundle/Contents/Info.plist"
done
SIGN_OPTIONS=(--force --sign "$IDENTITY" --options runtime)
if [[ "$IDENTITY" != "-" ]]; then SIGN_OPTIONS+=(--timestamp); fi
echo "==> Signing extensions, then host"
codesign "${SIGN_OPTIONS[@]}" --entitlements PreviewExtension/PreviewExtension.entitlements "$PE"
codesign "${SIGN_OPTIONS[@]}" --entitlements ThumbnailExtension/ThumbnailExtension.entitlements "$TE"
codesign "${SIGN_OPTIONS[@]}" --entitlements Peekdown/Peekdown.entitlements "$DEST"
for bundle in "$PE" "$TE" "$DEST"; do
    codesign --verify --strict --verbose=2 "$bundle"
done
codesign --verify --deep --strict --verbose=2 "$DEST"
echo "==> Built: $DEST (identity: $IDENTITY)"
