#!/usr/bin/env bash
#
# Builds Mac Duo.app from the SwiftPM package.
#
#   ./build.sh            build and sign
#   ./build.sh --run      build, sign, and relaunch the app
#   ./build.sh --universal  build for Apple Silicon and Intel
#
# Uses a stable available signing certificate when possible. Ad-hoc fallback
# requires new Screen Recording consent after rebuilds. Override with SIGN_IDENTITY.

set -euo pipefail
cd "$(dirname "$0")"

# A stable certificate keeps macOS privacy grants valid across rebuilds.
# Prefer a Developer ID identity, then a single local development identity.
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY="$(python3 - <<'SIGNPY'
import re, subprocess
text = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
for prefix in ['Developer ID Application:', 'Apple Development:']:
    matches = re.findall(r'([A-F0-9]{40}) "' + re.escape(prefix), text)
    if len(matches) == 1:
        print(matches[0]); break
    if len(matches) > 1:
        raise SystemExit('Multiple signing identities: set SIGN_IDENTITY explicitly.')
else:
    print('-')
SIGNPY
)"
fi
if [[ "$SIGN_IDENTITY" == - ]]; then
  echo 'Warning: ad-hoc signing can invalidate Screen Recording permission after each rebuild.' >&2
fi
APP_NAME="Mac Duo Private"
OUTPUT_BUNDLE="build/${APP_NAME}.app"
BUILD_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/mac-duo-build.XXXXXX")
trap 'rm -rf "$BUILD_STAGE"' EXIT
BUNDLE="$BUILD_STAGE/${APP_NAME}.app"

BUILD_ARGS=(-c release)
RUN_APP=false
for argument in "$@"; do
  case "$argument" in
    --universal) BUILD_ARGS+=(--arch arm64 --arch x86_64) ;;
    --run) RUN_APP=true ;;
    *) echo "Unknown argument: $argument" >&2; exit 1 ;;
  esac
done

swift build "${BUILD_ARGS[@]}" --product MacDuo

BIN_PATH="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
BINARY="$BIN_PATH/MacDuo"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BINARY" "$BUNDLE/Contents/MacOS/MacDuo"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp LICENSE NOTICE PRIVACY.md "$BUNDLE/Contents/Resources/"
cp Resources/PrivacyInfo.xcprivacy "$BUNDLE/Contents/Resources/"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

TIMESTAMP=--timestamp
if [[ "$SIGN_IDENTITY" == - ]]; then
  TIMESTAMP=--timestamp=none
fi
codesign --force --options runtime "$TIMESTAMP" \
  --sign "$SIGN_IDENTITY" "$BUNDLE"
codesign --verify --strict --verbose=1 "$BUNDLE"

mkdir -p build
rm -rf "$OUTPUT_BUNDLE"
cp -RX "$BUNDLE" "$OUTPUT_BUNDLE"
BUNDLE="$OUTPUT_BUNDLE"
echo "built ${BUNDLE}"
codesign -dv "$BUNDLE" 2>&1 | grep -E "Identifier|TeamIdentifier|Signature" || true

if "$RUN_APP"; then
  pkill -f -x "$PWD/$BUNDLE/Contents/MacOS/MacDuo" 2>/dev/null || true
  sleep 0.5
  open "$BUNDLE"
  echo "launched"
fi
