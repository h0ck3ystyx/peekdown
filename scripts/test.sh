#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
ARCH=$(uname -m)
NATIVE=$(./scripts/build-native-support.sh "$ARCH")
ditto "$NATIVE/SwiftMath_SwiftMath.bundle" build/tests/SwiftMath_SwiftMath.bundle
xcrun swiftc -I "$NATIVE/Modules" -L "$NATIVE" -lPeekdownNativeSupport -framework AppKit -framework QuickLookUI Shared/MarkdownText.swift Shared/RenderingConstants.swift Shared/PreviewSettings.swift Shared/StaticMDX.swift \
  PreviewExtension/PreviewImageAttachment.swift PreviewExtension/CodeBlockLayoutManager.swift PreviewExtension/SyntaxHighlighter.swift PreviewExtension/YAMLValidator.swift PreviewExtension/YAMLPreview.swift PreviewExtension/MarkdownRenderer.swift PreviewExtension/PreviewViewController.swift \
  Tests/YAMLCases.swift Tests/main.swift -o build/tests/regressions
build/tests/regressions
