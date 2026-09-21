# Development

Stillwater uses Swift, AppKit, SwiftUI, SpriteKit, Combine, and the Carbon hotkey API. There are no external libraries or runtime downloads. The release build is arm64, with a macOS 14 deployment target.

## Code map

| File | Responsibility |
| --- | --- |
| `Sources/Model.swift` | Saved settings, species, framing, swimming/feeding states, pellet scheduling, and bubble lifecycles |
| `Sources/AquariumScene.swift` | SpriteKit rendering, body/fin shaders, day/night fade, particles, and pause behavior |
| `Sources/Artwork.swift` | Images, pose rectangles, correspondence texture, cached motion masks, and contact shadows |
| `Sources/FishRendering.swift` | One-view turn warping and body/fin motion |
| `Sources/BubbleRendering.swift` | Refractive bubble shading and directional highlights |
| `Sources/WaterRendering.swift` | Masked vegetation sway, surface ripples, and moving light |
| `Sources/SettingsView.swift` | Native light/dark settings interface |
| `Sources/Application.swift` | Desktop windows, menus, global shortcut integration, exports, lifecycle, and native verification |
| `Sources/FeedingShortcut.swift` | Registration and cleanup of one global keyboard shortcut |
| `Tests/ModelTests.swift` | Deterministic behavioral and settings checks |

## Build and test

```sh
zsh tools/test.sh
zsh tools/build.sh
```

The build script archives any previous local app bundle under `build/`, compiles the executable, copies only current artwork and the license, then ad-hoc signs the app. Use a current Apple command-line toolchain. CI performs model tests, compilation, bundle validation, and architecture checks on an Apple Silicon macOS runner.

Native verification requires a logged-in macOS graphical session:

```sh
build/Stillwater.app/Contents/MacOS/Stillwater --review "$PWD/build/review"
```

This opens test windows and desktop surfaces, captures the renderer and settings, exercises production controls, checks day/night and Still mode, exports at display resolution, and writes `report.json`. It uses ephemeral preferences and does not change the system wallpaper. Appearance testing overrides only the test app’s appearance. Close another running Stillwater instance if you want the global shortcut registration check to acquire its usual key combination.

The native captures do not photograph Finder or other applications. AppKit bitmap caching omits Metal layers, so settings images substitute a renderer export for the preview layer. See [validation](../VALIDATION.md).

Native shader regression checks also require a graphical session:

```sh
zsh tools/test-rendering.sh
```

These render real SpriteKit shader output. A red/blue fixture detects accidental crossfading of separate fish views. Each scene is checked for independently moving plants and water, zero-intensity behavior, and complete Still freezing. Enlarged fish-turn and bubble-material captures are saved under `build/rendering-review/`.

### Fish turn correspondence

Turning uses a single visible photographic view at any instant. It warps that view toward the intermediate angle using precomputed, smoothed image correspondence instead of dissolving two photographs. Body opacity stays solid; source fin transparency is preserved. The small binary field is shared by every fish, and the app performs no runtime optical-flow or machine-learning work.

`Resources/Fish/turn-correspondence.flow` contains a 1024×1024 RGBA8 data texture, with eight columns of pose pairs and two rows per species (forward/backward). RG encode signed normalized displacement around 128 with a scale of 254. To regenerate it on a Mac with a native graphics session:

```sh
xcrun swiftc -swift-version 5 -O -module-cache-path build/module-cache \
  -framework AppKit -framework Vision -framework SpriteKit -framework Combine \
  Sources/Model.swift Sources/Artwork.swift tools/generate-fish-flow.swift -o build/generate-fish-flow
build/generate-fish-flow
```

This offline tool uses Apple's Vision framework on the existing artwork. Correspondence is regularized and bounded to avoid folded fins. View changes can still be noticeable in enlarged inspections; these are eight photographic-style views, not a complete 3D fish.

## Simulation details

Fish and scenery share an image-space transform, with the sand anchored to the bottom across aspect ratios. Each fish keeps an identity, velocity, continuous turn angle, mood, fin phase, appetite, and temporary feeding response. Still mode returns before advancing any simulation clock.

Feeding schedules three short sprinkles at changing horizontal locations. Pellets vary in release delay, size, rotation, drift, surface pause, and sinking speed. Pending and visible pellets share a bounded population budget. Fish notice food at different times, select targets, eat within mouth reach, and return to separate resting locations. Unreachable food is abandoned.

Bubbles have their own deterministic random stream, so enabling them does not change fish decisions. Each bubble has a source, delay, rise speed, drift, size, and lifetime. A respawn selects a different source. Bubbles ease into buoyant rise; larger ones rise faster, with small continuous lateral drift. Their shader adds a clear center, directional reflections, and a darker curved edge. All bubbles freeze in Still mode. Bubbles remain independent of the swimming-speed setting.

Vegetation and water masks are derived once per scene from the bundled artwork and cached. The background shader bends leaf regions with height above the bed, ripples the upper water surface, and moves light across sand and stones. The existing Plant sway and Water movement sliders independently control these effects. Night reduces light intensity, and Still freezes the shared clock.

## Packaging

```sh
zsh tools/package.sh
```

This produces ZIP and DMG archives plus `dist/SHA256SUMS.txt`. The DMG includes an Applications shortcut, installation notes, and the MIT license. Release binaries are uploaded as GitHub release assets, never committed into source history. The source tag and app version must match before publishing.

A Developer ID certificate and Apple notarization are not included in the current workflow. Anyone distributing their own signed build should use their own signing identity and credentials.

## Current limits and future work

- Fish use generated photographic-style views and shader deformation; this is not full 3D geometry.
- General schooling still uses shared group targets. Richer spontaneous splitting/rejoining and depth-aware swimming remain future work.
- Scene plants are part of image plates, with localized texture motion.
- The app has been exercised on the local M4/macOS 27 setup. Other physical displays, Spaces/Stage Manager combinations, and older OS versions need more hands-on testing.
- Sustained GPU power, thermal, and battery performance are not established by short native test samples.

Report reproducible problems with your macOS version, chip, display arrangement, scene, population, and rendering quality. Do not include personal screenshots unless needed and intentionally shared.
