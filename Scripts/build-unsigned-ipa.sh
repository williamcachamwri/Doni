#!/bin/sh
# Builds an unsigned Release IPA and checks that what came out is the version it says it is.
#
# Unsigned on purpose: this app is signed with a free personal team, so a build signed here cannot be
# installed by anybody else anyway. The artefact is for archiving and for a reader to re-sign with
# their own team.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD=${BUILD_DIR:-$ROOT/build}
DERIVED=$BUILD/DerivedData
APP=$DERIVED/Build/Products/Release-iphoneos/Doni.app
IPA=$BUILD/Doni.unsigned.ipa

cd "$ROOT"

# The notes are a bundle resource, so they have to be right before the compile rather than after.
python3 Scripts/release-notes.py

# project.yml is the only project file; regenerating it is what makes MARKETING_VERSION and
# CURRENT_PROJECT_VERSION land in the build. DONI_TEAM_ID is empty here on purpose — signing is off.
DONI_TEAM_ID="${DONI_TEAM_ID:-}" xcodegen --spec project.yml --quiet

xcodebuild clean build \
  -project Doni.xcodeproj -scheme Doni -configuration Release \
  -destination "generic/platform=iOS" -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" PROVISIONING_PROFILE="" \
  PROVISIONING_PROFILE_SPECIFIER=""

test -f "$APP/ReleaseNotes.json" || { echo "ipa: ReleaseNotes.json is not in the bundle"; exit 1; }

# The tag a release is cut under has to be the version inside the app, or the About screen and the
# release page disagree and the update check tells people they are behind when they are not.
BUNDLED=$(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist")
BUILD_NUMBER=$(plutil -extract CFBundleVersion raw "$APP/Info.plist")
IDENTIFIER=$(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")
if [ -n "${GITHUB_REF_NAME:-}" ]; then
  [ "$GITHUB_REF_NAME" = "v$BUNDLED" ] || {
    echo "ipa: tag $GITHUB_REF_NAME does not match the bundled version v$BUNDLED"; exit 1; }
fi
echo "ipa: Doni $BUNDLED (build $BUILD_NUMBER) as $IDENTIFIER"

STAGING=$BUILD/ipa-payload
rm -rf "$STAGING" && mkdir -p "$STAGING/Payload"
ditto --norsrc "$APP" "$STAGING/Payload/Doni.app"
rm -f "$IPA"
ditto -c -k --norsrc --keepParent "$STAGING/Payload" "$IPA"
unzip -tq "$IPA" > /dev/null
echo "ipa: wrote $IPA (notes: build/ReleaseNotes.md)"
