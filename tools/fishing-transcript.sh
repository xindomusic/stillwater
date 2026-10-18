#!/bin/zsh
# Scripted anglers fish the simulation headlessly and report bites, catches, and losses for
# every hook and bait. `--story` prints the event-by-event story of a few sessions instead.
set -euo pipefail
cd "${0:A:h:h}"
source tools/sources.zsh
mkdir -p build/module-cache
xcrun swiftc $swift_flags -framework Combine $model_sources Tests/FishingTranscript.swift -o build/fishing-transcript
build/fishing-transcript "$@"
