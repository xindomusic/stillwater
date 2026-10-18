# Single source of truth for compiler inputs, sourced by every tool script.
# Adding a source file means adding it here once (build.sh's app target globs
# Sources/*.swift, so the app picks new files up automatically).

# Swift 6 language mode (strict concurrency) for every target since 1.8.0.
swift_flags=(-swift-version 6 -O -module-cache-path build/module-cache)

# Foundation/Combine-only simulation and settings code, testable without a GPU.
model_sources=(
  Sources/Configuration.swift
  Sources/Dice.swift
  Sources/FishBehavior.swift
  Sources/Bubbles.swift
  Sources/Sand.swift
  Sources/Simulation.swift
  Sources/SimulationFeeding.swift
  Sources/SimulationBed.swift
  Sources/WallpaperStills.swift
)

# Model code (minus wallpaper file handling) plus the SpriteKit rendering layer.
rendering_sources=(
  Sources/Configuration.swift
  Sources/Dice.swift
  Sources/FishBehavior.swift
  Sources/Bubbles.swift
  Sources/Sand.swift
  Sources/Simulation.swift
  Sources/SimulationFeeding.swift
  Sources/SimulationBed.swift
  Sources/Artwork.swift
  Sources/FishRendering.swift
  Sources/BubbleRendering.swift
  Sources/WaterRendering.swift
  Sources/PelletRendering.swift
  Sources/AquariumScene.swift
)
