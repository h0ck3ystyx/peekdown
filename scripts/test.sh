#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
xcrun swiftc -framework AppKit -framework QuickLookUI Shared/MarkdownText.swift Shared/RenderingConstants.swift \
  PreviewExtension/CodeBlockLayoutManager.swift PreviewExtension/SyntaxHighlighter.swift PreviewExtension/MarkdownRenderer.swift PreviewExtension/PreviewViewController.swift \
  Tests/main.swift -o build/tests/regressions
build/tests/regressions
