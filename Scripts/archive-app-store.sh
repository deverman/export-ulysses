#!/bin/zsh
set -euo pipefail

team=${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Developer team ID.}
version=${1:-1.0.0}
build=${2:-1}
archive=${3:-"$PWD/dist/Export Ulysses-${version}.xcarchive"}

mkdir -p "${archive:h}"
xcodebuild \
  -project ExportUlysses.xcodeproj \
  -scheme "Export Ulysses" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$archive" \
  DEVELOPMENT_TEAM="$team" \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="$build" \
  archive

open "$archive"
