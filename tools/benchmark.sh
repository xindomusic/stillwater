#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source tools/sources.zsh
mkdir -p build/module-cache
xcrun swiftc $swift_flags \
  -framework AppKit -framework SpriteKit -framework Combine \
  $rendering_sources Tests/PerformanceProbe.swift -o build/performance-probe
build/performance-probe "$@"
