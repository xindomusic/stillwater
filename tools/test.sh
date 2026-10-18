#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source tools/sources.zsh
mkdir -p build/module-cache
xcrun swiftc $swift_flags -framework Combine $model_sources Tests/ModelTests.swift -o build/model-tests
build/model-tests
