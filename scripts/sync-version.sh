#!/bin/bash
# Requires Python 3 (provided by the Xcode developer tools / GitHub runners).
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 scripts/sync-version.py "$@"
