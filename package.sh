#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
APP='build/Mac Duo Private.app'
test -d "$APP" || { echo 'Run ./build.sh first.' >&2; exit 1; }
mkdir -p dist
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/mac-duo-package.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
# Exclude Finder/FileProvider metadata added to bundles in synced folders.
cp -RX "$APP" "$STAGING/"
codesign --verify --strict "$STAGING/Mac Duo Private.app"
cp README.md PRIVACY.md LICENSE NOTICE "$STAGING/"
cp docs/INSTALL.md "$STAGING/INSTALL.md"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname 'Mac Duo Private' -srcfolder "$STAGING" -ov -format UDZO 'dist/Mac-Duo-Private.dmg'
ditto -c -k --sequesterRsrc --keepParent "$STAGING/Mac Duo Private.app" 'dist/Mac-Duo-Private.zip'
tar -czf dist/Mac-Duo-Private-Source.tar.gz Sources Tests Resources Package.swift build.sh package.sh README.md PRIVACY.md LICENSE NOTICE .gitignore docs
(cd dist && shasum -a 256 Mac-Duo-Private.dmg Mac-Duo-Private.zip Mac-Duo-Private-Source.tar.gz > SHA256SUMS.txt)
