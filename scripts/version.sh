#!/bin/bash
# Source from the repository root. Explicit overrides are useful for test builds.
VERSION="${VERSION:-$(cat VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(cat BUILD_NUMBER)}"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || { echo 'Invalid VERSION' >&2; return 1; }
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid BUILD_NUMBER' >&2; return 1; }
export VERSION BUILD_NUMBER
