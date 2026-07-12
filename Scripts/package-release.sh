#!/bin/zsh
set -euo pipefail

version=${1:?usage: package-release.sh VERSION ARCH}
arch=${2:?usage: package-release.sh VERSION ARCH}
name="export-ulysses-${version}-macos26-${arch}"

swift build -c release --arch "$arch"
binary=".build/${arch}-apple-macosx/release/export-ulysses"
test -x "$binary"
test "$("$binary" --version)" = "$version"

mkdir -p "dist/$name"
cp "$binary" "dist/$name/export-ulysses"
cp README.md LICENSE "dist/$name/"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "dist/$name/export-ulysses"
  codesign --verify --strict --verbose=2 "dist/$name/export-ulysses"
fi

ditto -c -k --keepParent "dist/$name" "dist/$name.zip"

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  xcrun notarytool submit "dist/$name.zip" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait
fi

shasum -a 256 "dist/$name.zip" > "dist/$name.zip.sha256"
rm -rf "dist/$name"
