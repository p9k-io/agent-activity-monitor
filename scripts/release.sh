#!/bin/sh
# Builds, signs, notarizes and packages a release of the app, on the maintainer's Mac.
#
# No secret is in the repository or in CI. The signing identity is in the keychain, the App
# Store Connect key in ~/.appstoreconnect/private_keys, and the identifier of its issuer in
# ~/.config/agent-activity-monitor/asc-issuer-id.
#
#   scripts/release.sh                everything, ending with a notarized disk image in dist/
#   scripts/release.sh --no-notarize  stops short of Apple: built, signed and packaged only
#
# Nothing is published: uploading the disk image and merging the release pull request are
# separate steps a person takes (docs/RELEASING.md).
set -eu
cd "$(dirname "$0")/.."

notarize=1
[ "${1:-}" = "--no-notarize" ] && notarize=0

identity="${AAM_SIGN_IDENTITY:-Developer ID Application: Prokop Simek (ZHU9NYW7PP)}"
team="${AAM_TEAM:-ZHU9NYW7PP}"
version=$(sed -n 's/^ *MARKETING_VERSION: "\([^"]*\)".*/\1/p' App/project.yml)
name="Agent Activity Monitor"
out=dist
app="$out/$name.app"
image="$out/Agent-Activity-Monitor-$version.dmg"

say() { printf '\n== %s\n' "$1"; }
fail() { echo "release: $1" >&2; exit 1; }

security find-identity -v -p codesigning | grep -qF "$identity" \
  || fail "the signing identity \"$identity\" is not in the keychain."

# An app without the key that updates must be signed with could never be updated safely.
if grep -q "SPARKLE_PUBLIC_KEY" App/Info.plist; then
  fail "App/Info.plist has no update key yet. See docs/RELEASING.md, \"Once\"."
fi

if [ "$notarize" = 1 ]; then
  key="${AAM_ASC_KEY:-$(ls "$HOME"/.appstoreconnect/private_keys/AuthKey_*.p8 2>/dev/null | head -1)}"
  [ -f "$key" ] || fail "no App Store Connect key in ~/.appstoreconnect/private_keys."
  key_id=$(basename "$key" .p8 | sed 's/^AuthKey_//')
  issuer_file="$HOME/.config/agent-activity-monitor/asc-issuer-id"
  [ -s "$issuer_file" ] || fail "the issuer identifier is missing: put it in $issuer_file."
  issuer=$(tr -d '[:space:]' < "$issuer_file")
fi

# Sends a file to Apple and waits for the verdict.
submit() {
  xcrun notarytool submit "$1" --key "$key" --key-id "$key_id" --issuer "$issuer" --wait
}

sign() {
  codesign --force --options runtime --timestamp --sign "$identity" "$@"
}

say "Building $name $version"
rm -rf "$out"
mkdir -p "$out"
xcodegen generate --spec App/project.yml --quiet
xcodebuild archive \
  -project App/AgentActivityMonitor.xcodeproj \
  -scheme AgentActivityMonitor \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$out/AgentActivityMonitor.xcarchive" \
  -derivedDataPath build/DerivedData \
  -quiet \
  ARCHS=arm64 \
  ENABLE_HARDENED_RUNTIME=YES \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$identity" \
  DEVELOPMENT_TEAM="$team"
ditto "$out/AgentActivityMonitor.xcarchive/Products/Applications/$name.app" "$app"

say "Adding the command line tool"
swift build -c release --arch arm64 --product aam
mkdir -p "$app/Contents/Helpers"
cp .build/arm64-apple-macosx/release/aam "$app/Contents/Helpers/aam"

say "Signing, from the inside out"
sparkle="$app/Contents/Frameworks/Sparkle.framework"
if [ -d "$sparkle" ]; then
  for part in \
    "$sparkle/Versions/B/XPCServices/Installer.xpc" \
    "$sparkle/Versions/B/XPCServices/Downloader.xpc" \
    "$sparkle/Versions/B/Autoupdate" \
    "$sparkle/Versions/B/Updater.app" \
    "$sparkle"; do
    [ -e "$part" ] && sign "$part"
  done
fi
sign --identifier io.p9k.agent-activity-monitor.aam "$app/Contents/Helpers/aam"
sign "$app"
codesign --verify --deep --strict "$app"
[ "$("$app/Contents/Helpers/aam" --version)" = "$version" ] \
  || fail "the command line tool does not report version $version."

if [ "$notarize" = 1 ]; then
  say "Notarizing the app"
  ditto -c -k --keepParent "$app" "$out/app.zip"
  submit "$out/app.zip"
  rm "$out/app.zip"
  xcrun stapler staple "$app"
fi

say "Packaging"
stage=$(mktemp -d)
ditto "$app" "$stage/$name.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "$name" -srcfolder "$stage" -ov -format UDZO -quiet "$image"
rm -rf "$stage"
codesign --force --timestamp --sign "$identity" "$image"

if [ "$notarize" = 1 ]; then
  say "Notarizing the disk image"
  submit "$image"
  xcrun stapler staple "$image"
  xcrun stapler validate "$image"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$image"
  spctl --assess --verbose=2 "$app"
fi

# The update feed, when Sparkle's tool and its signing key are at hand.
appcast=build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast
if [ -x "$appcast" ] && [ -d "$sparkle" ]; then
  say "Writing the update feed"
  feed=$(mktemp -d)
  cp "$image" "$feed/"
  "$appcast" --download-url-prefix "https://github.com/p9k-io/agent-activity-monitor/releases/download/v$version/" "$feed"
  cp "$feed/appcast.xml" "$out/appcast.xml"
  rm -rf "$feed"
fi

say "Done"
echo "$image"
echo "sha256 $(shasum -a 256 "$image" | cut -d' ' -f1)"
[ "$notarize" = 1 ] || echo "Not notarized: this build is for looking at, not for giving to anyone."
