#!/bin/bash
# Builds a self-contained, offline .app. No third-party libraries or services.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIGURATION="${1:-release}"
case "$CONFIGURATION" in debug|release) ;; *) echo "Usage: scripts/build-app.sh [debug|release] [--universal]" >&2; exit 1 ;; esac
ARCHITECTURES=(--arch "$(uname -m)")
if [[ "${2:-}" == "--universal" ]]; then ARCHITECTURES=(--arch arm64 --arch x86_64); fi
swift build -c "$CONFIGURATION" "${ARCHITECTURES[@]}"
BINARY_DIRECTORY="$(swift build -c "$CONFIGURATION" "${ARCHITECTURES[@]}" --show-bin-path)"
mkdir -p build
STAGING_DIRECTORY="$(mktemp -d "$PWD/build/.app-XXXXXX")"
trap 'rm -rf "$STAGING_DIRECTORY"' EXIT
APP="$STAGING_DIRECTORY/NotchBible.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY_DIRECTORY/NotchBible" "$APP/Contents/MacOS/NotchBible"
for TEXT_FILE in Sources/BibleCore/Resources/*.[tT][xX][tT]; do
    [[ -f "$TEXT_FILE" ]] && cp "$TEXT_FILE" "$APP/Contents/Resources/"
done
cp THIRD-PARTY-NOTICES.md "$APP/Contents/Resources/"
cp packaging/Info.plist "$APP/Contents/Info.plist"
swift scripts/make-icon.swift "$STAGING_DIRECTORY/NotchBible.iconset"
iconutil -c icns "$STAGING_DIRECTORY/NotchBible.iconset" -o "$APP/Contents/Resources/NotchBible.icns"
if [[ "${SIGN_IDENTITY:--}" == "-" ]]; then
    codesign --force --sign - "$APP"
else
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$APP"
fi
"$APP/Contents/MacOS/NotchBible" --check
rm -rf build/NotchBible.app
mv "$APP" build/NotchBible.app
echo "Built $PWD/build/NotchBible.app"
