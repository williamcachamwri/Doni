#!/bin/sh
# Builds the unsigned IPA on this machine and publishes it as the GitHub release.
#
# Not CI: the artefact a runner produces cannot be installed by anybody without re-signing anyway,
# and the macOS queue costs more wall clock than the compile. CI still has the same script for the
# "does this build from a clean checkout" question — run it by hand there.
#
# Needs `gh` authenticated with the repo, and XcodeGen + CMake + a built Vendor/ tree.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

for tool in gh xcodegen; do
  command -v "$tool" >/dev/null || { echo "release: $tool is required"; exit 1; }
done

BRANCH=$(git rev-parse --abbrev-ref HEAD)
sh Scripts/build-unsigned-ipa.sh

PLIST="build/DerivedData/Build/Products/Release-iphoneos/Doni.app/Info.plist"
VERSION=$(plutil -extract CFBundleShortVersionString raw "$PLIST")
BUILD=$(plutil -extract CFBundleVersion raw "$PLIST")
TAG="v$VERSION"

# The tag has to name the commit being released, or the About screen and the release page describe
# two different builds. Re-tagging is allowed while no release exists for it yet.
git tag -f -a "$TAG" -m "Doni $TAG — build $BUILD"

echo "release: pushing $BRANCH and $TAG"
git push origin "$BRANCH"
git push -f origin "refs/tags/$TAG"

# The body comes from RELEASE_NOTES.md through the build script, so a release cannot say something
# the app's own Release notes screen does not.
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "release: updating $TAG"
  gh release edit "$TAG" --title "Doni $TAG" --notes-file build/ReleaseNotes.md
  gh release upload "$TAG" build/Doni.unsigned.ipa --clobber
else
  echo "release: creating $TAG"
  gh release create "$TAG" \
    --title "Doni $TAG" \
    --notes-file build/ReleaseNotes.md \
    --verify-tag \
    "build/Doni.unsigned.ipa#Doni (unsigned) IPA"
fi

gh release view "$TAG" --json tagName,assets,url --jq '"\(.tagName) → \(.url)\n  assets: \([.assets[].name] | join(", "))"'
