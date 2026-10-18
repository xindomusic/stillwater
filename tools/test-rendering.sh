#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source tools/sources.zsh
mkdir -p build/module-cache
xcrun swiftc $swift_flags \
  -framework AppKit -framework SpriteKit -framework Combine \
  $rendering_sources Tests/RenderingTests.swift -o build/rendering-tests
# SpriteKit needs a real GPU/graphical session: without one (SSH, a sandboxed
# shell, no WindowServer) SKView creation segfaults inside SpriteKit before any
# project code runs. Report that plainly instead of a bare exit 139.
set +e
build/rendering-tests "$@"
rc=$?
set -e
if (( rc == 139 || rc == 134 )); then
  print -u2 "rendering-tests was killed (exit $rc), most likely while creating its SpriteKit view."
  print -u2 "That needs a logged-in graphical session with GPU access: run this from Terminal"
  print -u2 "on the Mac itself (as CI does on its macOS runner), not over SSH or in a sandbox."
fi
exit $rc
