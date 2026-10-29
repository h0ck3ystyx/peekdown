#!/bin/bash
# Run in a logged-in macOS desktop session after ./build.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d "$PWD/build/associations.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
APP="$TEST_DIR/Peekdown Association Test.app"
ditto build/local/Peekdown.app "$APP"
# Isolate this test from installed Peekdown and its registered Quick Look extensions.
rm -rf "$APP/Contents/PlugIns"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.markdownpreview.association-test' "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
printf '# Association test\n' > "$TEST_DIR/document.md"
xcrun swift Tests/FileAssociations.swift "$APP" "$TEST_DIR/document.md"
