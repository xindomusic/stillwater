#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app_dir="build/Stillwater.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")
name="Stillwater-${version}-macOS-arm64"
stage="build/package-${version}-$$"
mkdir -p dist "$stage"
/usr/bin/codesign --verify --strict "$app_dir"
/usr/bin/ditto "$app_dir" "$stage/Stillwater.app"
ln -s /Applications "$stage/Applications"
cp LICENSE "$stage/LICENSE.txt"
cp docs/INSTALL.md "$stage/READ-ME-FIRST.md"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_dir" "dist/${name}.zip"
/usr/bin/hdiutil create -volname "Stillwater ${version}" -srcfolder "$stage" -ov -format UDZO "dist/${name}.dmg"
cd dist
/usr/bin/shasum -a 256 "${name}.zip" "${name}.dmg" > SHA256SUMS.txt
print "Packaged ${name}.zip and ${name}.dmg"
