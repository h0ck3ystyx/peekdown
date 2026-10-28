#!/bin/bash
# Sync project.yml and Packaging/*.plist files with VERSION file
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION | tr -d '[:space:]')
BUILD_NUMBER="${1:-1}"

echo "Syncing version $VERSION (build $BUILD_NUMBER) to project files..."

# Update project.yml
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$VERSION\"/" project.yml
    sed -i '' "s/CURRENT_PROJECT_VERSION: \"[^\"]*\"/CURRENT_PROJECT_VERSION: \"$BUILD_NUMBER\"/" project.yml
else
    sed -i "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$VERSION\"/" project.yml
    sed -i "s/CURRENT_PROJECT_VERSION: \"[^\"]*\"/CURRENT_PROJECT_VERSION: \"$BUILD_NUMBER\"/" project.yml
fi

# Update Packaging plist files
for plist in Packaging/App-Info.plist Packaging/PreviewExt-Info.plist Packaging/ThumbExt-Info.plist; do
    if [[ "$OSTYPE" == "darwin"* ]]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$plist" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$plist" 2>/dev/null || true
    else
        # For Linux/CI, update using sed as a fallback
        sed -i "/<key>CFBundleShortVersionString<\/key>/{n;s|<string>[^<]*</string>|<string>$VERSION</string>|}" "$plist"
        sed -i "/<key>CFBundleVersion<\/key>/{n;s|<string>[^<]*</string>|<string>$BUILD_NUMBER</string>|}" "$plist"
    fi
done

echo "✓ Synced version $VERSION (build $BUILD_NUMBER) to:"
echo "  - project.yml"
echo "  - Packaging/App-Info.plist"
echo "  - Packaging/PreviewExt-Info.plist"
echo "  - Packaging/ThumbExt-Info.plist"
