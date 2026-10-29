#!/bin/bash
# Signed and notarized direct-distribution release. No credentials in the repo.
set -euo pipefail
cd "$(dirname "$0")"
if [[ "${1:-}" != "" && "${1:-}" != "--check" ]]; then
    echo 'Usage: release.sh [--check] (see RELEASE.md)' >&2; exit 1
fi
: "${APPLICATION_IDENTITY:?Set APPLICATION_IDENTITY to Developer ID Application: Name (TEAMID)}"
: "${INSTALLER_IDENTITY:?Set INSTALLER_IDENTITY to Developer ID Installer: Name (TEAMID)}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool Keychain profile}"
source scripts/version.sh
[[ "$APPLICATION_IDENTITY" == 'Developer ID Application: '* ]] || { echo 'Developer ID Application identity required' >&2; exit 1; }
[[ "$INSTALLER_IDENTITY" == 'Developer ID Installer: '* ]] || { echo 'Developer ID Installer identity required' >&2; exit 1; }
TEAM="${APPLICATION_IDENTITY##* (}"
TEAM="${TEAM%)}"
[[ "$TEAM" =~ ^[A-Z0-9]{10}$ && "$INSTALLER_IDENTITY" == *" ($TEAM)" ]] || { echo 'Certificates must belong to the same team' >&2; exit 1; }
for tool in swiftc lipo notarytool stapler; do xcrun --find "$tool" >/dev/null; done
for tool in pkgbuild productbuild; do command -v "$tool" >/dev/null; done
for identity in "$APPLICATION_IDENTITY" "$INSTALLER_IDENTITY"; do
    if ! security find-identity -v -p basic | grep -F -- "\"$identity\"" >/dev/null; then
        echo "Missing valid certificate with private key: $identity. See RELEASE.md." >&2; exit 1
    fi
done
echo '==> Checking notarization credentials'
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format plist >/dev/null
if [[ "${1:-}" == '--check' ]]; then
    echo 'Tool, certificate, and notarization credential checks passed.'
    exit 0
fi
export APPLICATION_IDENTITY INSTALLER_IDENTITY VERSION BUILD_NUMBER
OUT="$PWD/build/releases/$VERSION-$BUILD_NUMBER"
[[ ! -e "$OUT" ]] || { echo "Release directory already exists: $OUT" >&2; exit 1; }
./scripts/test.sh
./build.sh
mkdir -p "$OUT"
APP="$OUT/Peekdown.app"
ditto build/local/Peekdown.app "$APP"

# Check actual signatures rather than assuming the selected identity was used.
for bundle in "$APP/Contents/PlugIns/PreviewExtension.appex" "$APP/Contents/PlugIns/ThumbnailExtension.appex" "$APP"; do
    codesign --verify --strict --verbose=2 "$bundle"
    DETAILS=$(codesign -d --verbose=4 "$bundle" 2>&1)
    printf '%s\n' "$DETAILS" | grep -F "Authority=$APPLICATION_IDENTITY" >/dev/null
    printf '%s\n' "$DETAILS" | grep -Fx "TeamIdentifier=$TEAM" >/dev/null
    printf '%s\n' "$DETAILS" | grep -E 'flags=.*\(.*runtime' >/dev/null
    printf '%s\n' "$DETAILS" | grep '^Timestamp=' >/dev/null
    codesign -d --entitlements :- "$bundle" > "$OUT/entitlements.plist" 2>/dev/null
    if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$OUT/entitlements.plist" 2>/dev/null || true)" == true ]]; then
        echo 'Release contains get-task-allow entitlement' >&2; exit 1
    fi
done
rm "$OUT/entitlements.plist"
notarize() {
    local file="$1" label="$2" status submission result=0
    # Save Apple's submission ID even when submission fails or is rejected.
    xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" \
      --wait --output-format plist > "$OUT/$label-notary.plist" || result=$?
    status=""
    submission=""
    if plutil -lint "$OUT/$label-notary.plist" >/dev/null 2>&1; then
        status=$(/usr/libexec/PlistBuddy -c 'Print :status' "$OUT/$label-notary.plist" 2>/dev/null || true)
        submission=$(/usr/libexec/PlistBuddy -c 'Print :id' "$OUT/$label-notary.plist" 2>/dev/null || true)
    fi
    if [[ "$submission" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
        xcrun notarytool log "$submission" --keychain-profile "$NOTARY_PROFILE" "$OUT/$label-notary-log.json" || true
    fi
    [[ "$result" == 0 && "$status" == Accepted ]] || {
        echo "Notarization failed (status: ${status:-unknown}); inspect $OUT/$label-notary.plist and log. See RELEASE.md." >&2
        return 1
    }
}

ditto -c -k --keepParent "$APP" "$OUT/app-submission.zip"
notarize "$OUT/app-submission.zip" app
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/Peekdown-$VERSION.zip"
PKG="$OUT/Peekdown-$VERSION.pkg"
./scripts/package.sh "$APP" "$PKG"
./scripts/test-package.sh "$PKG"
pkgutil --check-signature "$PKG"
notarize "$PKG" installer
xcrun stapler staple "$PKG"
xcrun stapler validate "$PKG"
spctl --assess --type install --verbose=2 "$PKG"
(cd "$OUT" && shasum -a 256 "Peekdown-$VERSION.pkg" "Peekdown-$VERSION.zip" > SHA256SUMS)
echo "Release ready: $PKG"
