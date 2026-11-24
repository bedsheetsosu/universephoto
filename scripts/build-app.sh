#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
app_dir="$project_dir/build/UniverseStudio.app"
cd "$project_dir"
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/UniverseStudio" "$app_dir/Contents/MacOS/UniverseStudio"
cp "$project_dir/scripts/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/LICENSE" "$app_dir/Contents/Resources/LICENSE"
for b in "$bin_dir"/*.bundle; do rm -rf "$app_dir/Contents/Resources/${b:t}"; cp -R "$b" "$app_dir/Contents/Resources/"; done
cp -R "$project_dir/scripts/Localization/en.lproj" "$app_dir/Contents/Resources/"
cp -R "$project_dir/scripts/Localization/de.lproj" "$app_dir/Contents/Resources/"
icon_dir="$bin_dir/UniverseStudio.iconset"
swift "$project_dir/scripts/create-icon.swift" "$icon_dir"
/usr/bin/iconutil --convert icns --output "$app_dir/Contents/Resources/UniverseStudio.icns" "$icon_dir"
# A stable signature keeps keychain access (UniversePen's device keys) across rebuilds; an ad-hoc
# signature changes with every build, so macOS would ask for the keychain password each time.
# SIGN_IDENTITY overrides; otherwise the first valid "Apple Development" identity, else ad hoc.
identity="${SIGN_IDENTITY:-$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/awk '/Apple Development/ && !/REVOKED/ { print $2; exit }')}"
if [[ -n "$identity" ]] && /usr/bin/codesign --force --sign "$identity" "$app_dir" 2>/dev/null; then
  :
else
  /usr/bin/codesign --force --sign - "$app_dir"
fi
print -r -- "$app_dir"
