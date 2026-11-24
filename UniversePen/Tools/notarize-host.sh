#!/bin/zsh
# Builds UniversePen Host as a notarized, stapled Developer ID app (no "Open Anyway" needed).
#
# Needs the paid Apple Developer Program:
#   1. A "Developer ID Application" certificate in your login keychain.
#   2. A notarytool profile, created once:
#        xcrun notarytool store-credentials universepen --apple-id <your Apple ID> --team-id <TEAM>
#      (it asks for an app-specific password from account.apple.com)
#
# Usage:  TEAM_ID=ABCDE12345 Tools/notarize-host.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TEAM_ID:?set TEAM_ID to your Apple Developer team ID}"
PROFILE="${NOTARY_PROFILE:-universepen}"
VERSION="${1:-$(grep MARKETING_VERSION project.yml | head -1 | sed 's/.*"\(.*\)".*/\1/')}"
OUT="build/notarized"
rm -rf "$OUT/dd" && mkdir -p "$OUT"

xcodegen generate -q
xcodebuild -project Tafel.xcodeproj -scheme TafelHost -configuration Release \
  -derivedDataPath "$OUT/dd" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="$TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_ENTITLEMENTS=Host/UniversePenHost.entitlements \
  OTHER_CODE_SIGN_FLAGS="--timestamp" -quiet build

APP="$OUT/dd/Build/Products/Release/UniversePen Host.app"
codesign --verify --strict --deep "$APP"
ZIP="$OUT/UniversePen-Host-$VERSION-macOS.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Submitting to Apple's notary service (takes a few minutes) …"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"   # zip again with the stapled ticket
spctl --assess --type execute -v "$APP"
shasum -a 256 "$ZIP"
echo "Done: $ZIP"
