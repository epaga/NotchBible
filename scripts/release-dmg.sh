#!/bin/bash
# Creates a signed, notarized universal DMG for upload to GitHub Releases.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_KEYCHAIN_PROFILE:?Set NOTARY_KEYCHAIN_PROFILE to your notarytool Keychain profile}"
if [[ "$SIGN_IDENTITY" != "Developer ID Application:"* ]]; then
    echo "Release builds require a Developer ID Application identity." >&2
    exit 1
fi

# Ignored local translations are included by ordinary builds, but not releases.
for TEXT_FILE in Sources/BibleCore/Resources/*.[tT][xX][tT]; do
    if [[ -f "$TEXT_FILE" && "$TEXT_FILE" != "Sources/BibleCore/Resources/NETBible.txt" ]]; then
        echo "Release from a checkout containing only NETBible.txt; found $TEXT_FILE." >&2
        exit 1
    fi
done
xcrun notarytool history --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" >/dev/null
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' packaging/Info.plist)"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Set CFBundleShortVersionString to a version such as 1.0.0." >&2
    exit 1
fi
scripts/build-app.sh release --universal
APP="$PWD/build/NotchBible.app"
STAGING_DIRECTORY="$(mktemp -d "$PWD/build/.dmg-XXXXXX")"
trap 'rm -rf "$STAGING_DIRECTORY"' EXIT

notarize() {
    local ARTIFACT="$1" RESULT="$2" SUBMISSION_ID
    if ! xcrun notarytool submit "$ARTIFACT" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
        --wait --output-format json >"$RESULT"; then
        echo "Notarization submission failed; see $RESULT." >&2
        return 1
    fi
    if [[ "$(plutil -extract status raw -o - "$RESULT")" != "Accepted" ]]; then
        SUBMISSION_ID="$(plutil -extract id raw -o - "$RESULT")"
        xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
            "${RESULT%.json}.log.json" || true
        echo "Notarization was not accepted; see $RESULT and ${RESULT%.json}.log.json." >&2
        return 1
    fi
}

# Staple the app first so it also carries its ticket after copying to Applications.
ditto -c -k --keepParent "$APP" "$STAGING_DIRECTORY/NotchBible.zip"
notarize "$STAGING_DIRECTORY/NotchBible.zip" "$PWD/build/notary-app.json"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=2 "$APP"

mkdir "$STAGING_DIRECTORY/image"
ditto "$APP" "$STAGING_DIRECTORY/image/NotchBible.app"
ln -s /Applications "$STAGING_DIRECTORY/image/Applications"
DMG_NAME="NotchBible-$VERSION-universal.dmg"
DMG="$STAGING_DIRECTORY/$DMG_NAME"
hdiutil create -volname "NotchBible" -srcfolder "$STAGING_DIRECTORY/image" -format UDZO "$DMG"
codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
notarize "$DMG" "$PWD/build/notary-dmg.json"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
mv -f "$DMG" "build/$DMG_NAME"
(cd build && shasum -a 256 "$DMG_NAME" >"$DMG_NAME.sha256")
echo "Ready to upload: $PWD/build/$DMG_NAME and $PWD/build/$DMG_NAME.sha256"
