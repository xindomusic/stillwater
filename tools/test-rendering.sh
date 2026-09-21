#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -O -module-cache-path build/module-cache \
  -framework AppKit -framework SpriteKit -framework Combine \
  Sources/Model.swift Sources/Artwork.swift Sources/FishRendering.swift Sources/BubbleRendering.swift \
  Sources/WaterRendering.swift Sources/PelletRendering.swift Sources/AquariumScene.swift Tests/RenderingTests.swift -o build/rendering-tests
build/rendering-tests "$@"
