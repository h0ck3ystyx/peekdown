#!/bin/bash
# Uses only the macOS/Xcode tools; generated assets are committed for normal builds.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/icon Peekdown/Resources
xcrun swift scripts/generate-icon.swift build/icon/Peekdown.iconset
iconutil -c icns build/icon/Peekdown.iconset -o Peekdown/Resources/Peekdown.icns
