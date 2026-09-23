# Development

Stillwater uses Swift, AppKit, SwiftUI, SpriteKit, Combine, and the Carbon hotkey API. There are no external libraries or runtime downloads. The release build is arm64, with a macOS 14 deployment target.

## Code map

| File | Responsibility |
| --- | --- |
| `Sources/Dice.swift` | Per-individual seeded dice (xoshiro256**) with uniform, normal, exponential, and log-normal draws |
| `Sources/Configuration.swift` | Saved settings, themes, species traits, and the settings store |
| `Sources/FishBehavior.swift` | Per-fish state and temperament, framing, navigation, shrimp steps and escapes, crab gait, and fin strokes |
| `Sources/Simulation.swift` | The simulation step: moods, food choice, steering, banked turns, depth, pellets, and bubbles |
| `Sources/WallpaperStills.swift` | Saved wallpaper stills and pruning of stills no display uses |
| `Sources/AquariumScene.swift` | SpriteKit rendering, body/fin shaders, day/night fade, particles, and pause behavior |
| `Sources/Artwork.swift` | Images, pose rectangles, cached motion masks, and contact shadows |
| `Sources/FishRendering.swift` | Continuous curved-body projection and body/fin motion |
| `Sources/PelletRendering.swift` | Rounded pellet volumes, tumble, surface shading, and distance contrast |
| `Sources/BubbleRendering.swift` | Refractive bubble shading and directional highlights |
| `Sources/WaterRendering.swift` | Masked vegetation sway, surface ripples, and moving light |
| `Sources/SettingsView.swift` | Native light/dark settings interface |
| `Sources/Application.swift` | Desktop windows, menus, global shortcut integration, exports, and lifecycle |
| `Sources/ReviewMode.swift` | `--review` native verification and release report |
| `Sources/FeedingShortcut.swift` | Registration and cleanup of one global keyboard shortcut |
| `Tests/ModelTests.swift` | Deterministic behavioral and settings checks, as named cases that all run and all report |

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

### Continuous fish turns

The fish renderer projects one photographic profile onto a curved body with thin fin surfaces. A continuous heading rotates that surface in space; it never selects or dissolves between different pose photographs. The head leads an eased turn while a lateral spine curve bends the body and delays the tail. Each body pixel marches a short, bounded ray (4 steps for a side view, up to 20 head-on, plus a 4-step bisection) through the bent body volume and stops at the first opaque point of the photograph. This keeps head-on views solid: a single ellipsoid intersection used to land on the transparent area beyond the snout, which showed water through the middle of a turning fish. Fin coverage follows each fin surface's local angle.

A reversal is a banked U-turn rather than a spin in place. A fish keeps gliding along its body axis while its heading swings round, so its screen travel slows, passes through a three-quarter and head-on view, and speeds up in the new direction. Forward travel during the turn carries the fish nearer or farther, which changes its size a little, then it drifts back to its usual depth. Fish climb and dive along a gentle slope rather than rising vertically, and only a lasting horizontal intent flips the side a fish faces. A begun turn is finished, and a reversal swings away from the viewer when the fish is near the glass and toward it when far. A fish that spots food pivots toward it without drifting away. This is a lightweight photographic proxy, not a complete anatomical 3D model.

Each fish has a separate deterministic motor stream. Stroke strength and cadence ease between irregular swimming and gliding intervals, while acceleration and steering recruit stronger strokes. Pectoral and dorsal/anal motion have separate phases; fin roots and the face stay anchored. Gouramis have a slower cadence, and loaches have more distributed body flex. These are artistic tunings, not measured kinematics of the represented species. General inspiration includes experimental work on [speed-dependent fin recruitment](https://journals.biologists.com/jeb/article/211/4/587/18045/Speed-dependent-intrinsic-caudal-fin-muscle) and [coordination of fins during turns](https://journals.biologists.com/jeb/article/204/17/2943/32831/Locomotor-function-of-the-dorsal-fin-in-teleost).

Native rendering tests compare closely spaced frames around every former pose boundary, the head-on and rear views, and the full-turn wrap. A head-on check counts see-through pixels inside each fish's body. They also check that unrelated source colors are never blended into a double exposure.

### Chance and individuality

Every fish, shrimp, crab, bubble, and pellet owns a seeded `Dice` (xoshiro256** seeded through SplitMix64), so one individual's choices never change another's and every run can be replayed in tests. Chance follows the shapes seen in real animal movement rather than flat ranges. Waits between decisions and mood lengths are exponential: mostly short, now and then long. Course changes are normally distributed around straight ahead, with an occasional reversal. Between decisions the heading meanders in a slow, correlated drift (an Ornstein–Uhlenbeck process), so paths curve. Each fish also rolls a lasting temperament at birth (boldness, restlessness, sociability), so individuals of one species differ consistently.

Wandering fish cannot turn tighter than about a third of a body length, and they push a little harder through a turn, so large, slow fish swing through a visible arc instead of pivoting while small fish still turn briskly. Rising or diving, a fish swims forward along the slope, tipping up to about 25° when it strikes at food, rather than lifting straight up.

Crabs scuttle sideways in quick bursts of about half a body length, with frequent pauses. Most bursts continue the same way, some reverse, and a few are slower shuffles forward or back. Their legs step in proportion to the distance walked and rest when the crab stops. Shrimp walk in short leg-steps with pauses to pick at the sand, swim only when drifting up into the water, and dart away when a fish that would eat them (cherry and golden barbs, gouramis, bettas, koi) comes close, usually while it dives for food, then freeze for a moment. With no room on the far side of the bed, a shrimp shoots up off the sand instead. A threat ahead gives the classic backward tail flip; a threat behind, a forward dart. Loaches and danios are ignored. A fish leaving after a meal swims like a wanderer again, so it glides off instead of pivoting on the spot.

### Runtime efficiency

Fish profiles are lazily copied into small, independent texture buffers; the seven unused views in each source atlas are released after decoding. The six new standalone profiles are decoded into buffers no larger than 640×640 and loaded only when used. Desktop and preview surfaces share the current scene texture. A shared 120-resident cap keeps the larger catalogue within the previous simulation population budget. Per-fish shader attribute objects and separation-position storage are reused, constant sizes and UV rectangles are set outside the frame loop, and hidden atmosphere nodes skip positioning. Food targeting uses a single pass without temporary candidate arrays, and the number of fish chasing each pellet is kept up to date as fish choose, so a crowded feeding stays linear in the number of fish. Floating particles are textured sprites that batch into one GPU draw, and pellet and bubble shader values are reused rather than reallocated each frame. Still, hidden windows, and sleep retain their existing render-loop pause behavior.

`zsh tools/benchmark.sh build/performance.json` runs a controlled probe with two visible production surfaces. It reports physical memory footprint, CPU time, frame count, and retained fish texture bytes at default and maximum populations. Run comparisons sequentially on the same machine with similar background load. This short probe does not measure sustained battery use or GPU energy.

## Simulation details

Fish and scenery share an image-space transform, with the sand anchored to the bottom across aspect ratios. Each fish keeps an identity, velocity, continuous turn angle, pitch, mood, fin phase, appetite, and temporary feeding response. Still mode returns before advancing any simulation clock.

Each fish owns separate seeded streams for birth, navigation, motor rhythms, and mood/feeding responses. Navigation decisions arrive at irregular intervals: most change the heading by 10–45 degrees, some by 45–100 degrees, and a minority by 140–180 degrees, with either sign. Speed, maximum turn rate, viewing angle, and interest in nearby schoolmates also vary. Velocity and posture ease toward these intentions. Resting holds the current intention; feeding temporarily takes over steering. Soft edge anticipation keeps fish in their swimming regions. There is no shared sinusoidal route or command to rotate a full circle.

Swimmers have a maximum base pitch of about 13 degrees, reduced while resting or turning; bottom-dwelling loaches use a smaller limit. Pitch changes have an angular speed limit. During reversals, horizontal travel follows the facing direction so a fish cannot slide tail-first while its head catches up.

Crabs remain within each scene’s substrate region and crawl in varied horizontal and diagonal directions with small body-angle changes. Eight rooted leg regions use staggered stepping phases and knee lifts; the shell stays rigid. Shrimp use a separate seeded grazing/drifting/refuge state machine: they briefly swim above the bed, seek a planted or rocky edge, conceal themselves, and emerge again. Shelter occlusion wipes from the leading side at the refuge, keeping the remaining body opaque. Feeding interrupts hiding, and Still freezes the shelter clock. These are inexpensive photographic animation and occlusion approximations, not complete articulated meshes or a geometric reconstruction of each rock.

Rasboras and barbs can gently follow nearby companions through local position/velocity influence, using the same reusable neighbor buffer as separation. Their individual affinity changes over time, so that influence does not erase their own navigation choices.

Feeding schedules three short sprinkles at changing horizontal locations. Pellets vary in release delay, size, rotation, drift, surface pause, and sinking speed. Pending and visible pellets share a bounded population budget. Each portion spans three distance bands. Pellets use rounded 3D volumes with surface grain and directional shading, tumble while falling, and stop rotating as they settle. Fish notice food at different times, select targets, eat within mouth reach, and return to separate resting locations. Unreachable food is abandoned.

Each bubble retains its own deterministic random stream across respawns, so its lifecycle and enabling bubbles do not change fish decisions. Each bubble has a source, delay, rise speed, drift, size, and lifetime. A respawn selects a different source. Bubbles ease into buoyant rise; larger ones rise faster, with small continuous lateral drift. Their shader adds a clear center, directional reflections, and a darker curved edge. Their distance affects apparent size, rise speed, and contrast. Bubbles and food share the fish depth axis, so far particles pass behind fish and near particles pass in front. All bubbles freeze in Still mode. Bubbles remain independent of the swimming-speed setting.

Vegetation and water masks are derived once per scene from the bundled artwork and cached. The background shader bends leaf regions with height above the bed, ripples the upper water surface, and moves light across sand and stones. The existing Plant sway and Water movement sliders independently control these effects. Night reduces light intensity, and Still freezes the shared clock.

## Packaging

```sh
zsh tools/package.sh
```

This produces ZIP and DMG archives plus `dist/SHA256SUMS.txt`. The DMG includes an Applications shortcut, installation notes, and the MIT license. Release binaries are uploaded as GitHub release assets, never committed into source history. The source tag and app version must match before publishing.

A Developer ID certificate and Apple notarization are not included in the current workflow. Anyone distributing their own signed build should use their own signing identity and credentials.

## Current limits and future work

- Fish use generated photographic-style views and shader deformation; this is not full 3D geometry.
- Schooling uses limited local attraction/alignment and individual wandering. Full three-dimensional schooling and depth-aware swimming remain future work.
- Scene plants are part of image plates, with localized texture motion.
- The app has been exercised on the local M4/macOS 27 setup. Other physical displays, Spaces/Stage Manager combinations, and older OS versions need more hands-on testing.
- Sustained GPU power, thermal, and battery performance are not established by short native test samples.

Report reproducible problems with your macOS version, chip, display arrangement, scene, population, and rendering quality. Do not include personal screenshots unless needed and intentionally shared.
