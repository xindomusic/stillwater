#!/bin/zsh
# Renders scripted fishing sessions with the production renderer: key moments, a contact
# sheet, and a fight GIF. Needs a logged-in graphical session, like the rendering tests.
set -euo pipefail
cd "${0:A:h:h}"
source tools/sources.zsh
mkdir -p build/module-cache
xcrun swiftc $swift_flags \
  -framework AppKit -framework SpriteKit -framework Combine -framework SwiftUI \
  $rendering_sources Sources/FishingWindow.swift Tests/FishingCapture.swift -o build/fishing-capture
build/fishing-capture "${1:-build/fishing-review}"
