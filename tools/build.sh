#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app_dir="build/Stillwater.app"
# Archive the previous local bundle so obsolete development artwork cannot leak into a release.
if [[ -d "$app_dir" ]]; then
  previous_build="build/previous-bundle-$(date +%s)-$$"
  mv "$app_dir" "$previous_build"
fi
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources/Scenes" "$app_dir/Contents/Resources/Fish" build/module-cache
xcrun swiftc -swift-version 5 -O -module-cache-path build/module-cache -target arm64-apple-macos14.0 \
  -framework AppKit -framework SwiftUI -framework SpriteKit -framework Combine -framework UniformTypeIdentifiers -framework Carbon \
  Sources/*.swift -o build/Stillwater.app/Contents/MacOS/Stillwater
cp Resources/Info.plist build/Stillwater.app/Contents/Info.plist
cp Resources/Scenes/*-crystal.png build/Stillwater.app/Contents/Resources/Scenes/
cp Resources/Fish/*-turns.png build/Stillwater.app/Contents/Resources/Fish/
cp Resources/Fish/*.flow build/Stillwater.app/Contents/Resources/Fish/
cp LICENSE build/Stillwater.app/Contents/Resources/
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns build/Stillwater.app/Contents/Resources/; fi
/usr/bin/codesign --force --sign - build/Stillwater.app
print "Built: ${PWD}/build/Stillwater.app"
