#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
app_dir="$project_dir/build/UniversePhoto.app"
cd "$project_dir"
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/UniversePhoto" "$app_dir/Contents/MacOS/UniversePhoto"
cp "$project_dir/scripts/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/LICENSE" "$app_dir/Contents/Resources/LICENSE"
cp -R "$bin_dir/UniversePhoto_UniversePhoto.bundle" "$app_dir/Contents/Resources/"
cp -R "$project_dir/scripts/Localization/en.lproj" "$app_dir/Contents/Resources/"
cp -R "$project_dir/scripts/Localization/de.lproj" "$app_dir/Contents/Resources/"
icon_dir="$bin_dir/UniversePhoto.iconset"
swift "$project_dir/scripts/create-icon.swift" "$icon_dir"
/usr/bin/iconutil --convert icns --output "$app_dir/Contents/Resources/UniversePhoto.icns" "$icon_dir"
/usr/bin/codesign --force --sign - "$app_dir"
print -r -- "$app_dir"
