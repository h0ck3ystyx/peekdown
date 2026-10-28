#!/bin/bash
# Package an existing app without running registration commands as root.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:?Usage: scripts/package.sh APP OUTPUT.pkg}"
OUTPUT="${2:?Usage: scripts/package.sh APP OUTPUT.pkg}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
mkdir -p build
STAGING=$(mktemp -d "$PWD/build/package.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING/root/Applications"
ditto "$APP" "$STAGING/root/Applications/Peekdown.app"
pkgbuild --analyze --root "$STAGING/root" "$STAGING/components.plist"
# Never relocate an upgrade to an arbitrary copy of the app elsewhere on disk.
/usr/libexec/PlistBuddy -c 'Add :0:BundleIsRelocatable bool false' "$STAGING/components.plist"
/usr/libexec/PlistBuddy -c 'Set :0:BundleOverwriteAction upgrade' "$STAGING/components.plist"
SIGN_OPTIONS=(--ownership recommended)
if [[ -n "${INSTALLER_IDENTITY:-}" ]]; then
    SIGN_OPTIONS+=(--sign "$INSTALLER_IDENTITY" --timestamp)
fi
pkgbuild --root "$STAGING/root" --component-plist "$STAGING/components.plist" \
  --identifier com.markdownpreview.installer --version "$VERSION" \
  --install-location / "${SIGN_OPTIONS[@]}" "$OUTPUT"
