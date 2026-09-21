#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -O -module-cache-path build/module-cache -framework Combine Sources/Model.swift Tests/ModelTests.swift -o build/model-tests
build/model-tests
