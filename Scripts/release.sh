#!/bin/bash
# Builds the Mac release into build/Tape.zip and checks it.
#
#   Scripts/release.sh                       build and check only
#   Scripts/release.sh --publish NOTES.md    also create GitHub release vX.Y.Z from HEAD
#
# The bundle ID is set here rather than read from Config/Local.xcconfig, so a release built from
# any clone keeps the ID users already have. A different ID would give them an empty sandbox
# container, without their saved labels or their Bluetooth permission.
set -euo pipefail

bundle_id=com.williamlarsten.tape
cd "$(dirname "$0")/.."

fail() { echo "release: $*" >&2; exit 1; }

notes=
case "${1-}" in
  "") ;;
  --publish)
    notes=${2-}
    [[ -f $notes ]] || fail "--publish needs a release notes file"
    ;;
  *) fail "usage: Scripts/release.sh [--publish NOTES.md]" ;;
esac

version=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml)
build=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"$/\1/p' project.yml)
[[ -n $version && -n $build ]] || fail "couldn't read the version from project.yml"

if [[ -n $notes ]]; then
  [[ -z $(git status --porcelain) ]] || fail "commit or stash your changes first"
  git fetch -q origin main
  git merge-base --is-ancestor HEAD origin/main || fail "push HEAD to main first"
  ! gh release view "v$version" >/dev/null 2>&1 || fail "v$version already exists. Bump the version in project.yml."
fi

app=build/release/Build/Products/Release/Tape.app
zip=build/Tape.zip
rm -rf build/release "$zip"

# Ad-hoc signing needs no Apple developer account, and an empty team keeps a local one out.
xcodebuild -quiet -project Tape.xcodeproj -scheme Tape -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/release \
  TAPE_BUNDLE_ID="$bundle_id" DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- \
  build

codesign --verify --deep --strict "$app" || fail "the signature doesn't verify"
signature=$(codesign -dv "$app" 2>&1)
grep -qx 'Signature=adhoc' <<<"$signature" || fail "the app isn't ad-hoc signed"
grep -qx 'TeamIdentifier=not set' <<<"$signature" || fail "the app is signed with a team"

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$app/Contents/Info.plist"; }
[[ $(plist CFBundleIdentifier) == "$bundle_id" ]] || fail "bundle ID is $(plist CFBundleIdentifier), not $bundle_id"
[[ $(plist CFBundleShortVersionString) == "$version" ]] || fail "version is $(plist CFBundleShortVersionString), not $version. Run xcodegen generate."
[[ $(plist CFBundleVersion) == "$build" ]] || fail "build is $(plist CFBundleVersion), not $build. Run xcodegen generate."

ditto -c -k --keepParent "$app" "$zip"
echo "Built $zip: Tape $version ($build), $bundle_id, ad-hoc signed, $(du -h "$zip" | cut -f1 | tr -d ' ')."

if [[ -n $notes ]]; then
  gh release create "v$version" "$zip" --target "$(git rev-parse HEAD)" --title "Tape $version" --notes-file "$notes"
fi
