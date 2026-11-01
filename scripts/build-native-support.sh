#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ARCH="${1:?Usage: scripts/build-native-support.sh arm64|x86_64}"
[[ "$ARCH" == arm64 || "$ARCH" == x86_64 ]] || exit 1
swift build --scratch-path "build/native/$ARCH" -c release --arch "$ARCH" \
    --product PeekdownNativeSupport -Xswiftc -application-extension >&2
swift build --scratch-path "build/native/$ARCH" -c release --arch "$ARCH" --show-bin-path
