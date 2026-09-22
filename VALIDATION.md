# Stillwater 1.1.0 validation

Validated September 21, 2026 on an Apple M4, macOS 27.0, with one 3440×1440 display. The app targets Apple Silicon and macOS 14+. Older supported macOS versions have not been tested locally.

## Automated model checks

`zsh tools/test.sh` passes. Coverage includes:

- Saved configuration, migration, sanitization, stable fish identities, ten-species persistence, and a shared 120-resident limit. New species start at zero on upgrade.
- Bounded upright pitch, gentle attitude changes, and head-first travel during reversals.
- Independent shrimp grazing, drifting, refuge seeking, hiding, and emergence in all three scenes; varied crab crawl directions, rigid level shells, and frozen refuge timers in Still.
- Thirty simulated minutes across scenes, 120-fish populations, bounded wake-up deltas, and standard, ultrawide, and portrait framing.
- Eased angular acceleration, curved-body turns, hovering, cruising, dashing, foraging, and fin motion.
- Independent navigation with small/wide turns and reversals in both directions; varied decision timing, pace, and turn rate; resting and Still hold navigation.
- Separate per-fish navigation/mood/motor streams and per-bubble random states; enabling bubbles leaves fish trajectories identical.
- Independent motor streams, non-repeating cadence/strength at constant speed, smooth stroke transitions, weaker gliding tails, and stronger dashes.
- All ten species in all three scenes reacting to feeding within 1.5 seconds; approach, consumption, departure, and abandonment of unreachable food.
- Staggered pellet releases from varied locations, different sizes and sinking speeds, portion limits, expiry, and scene-change cleanup.
- Bubble origins changing on respawn, distribution across the water, and bubble movement independent of fish swimming speed.
- Near, middle, and far particle distribution, with depth-dependent apparent size.
- Complete Still freezing of fish, fins, turns, reaction timers, visible and pending food, pellet tumble, and bubbles.

## Native shader regression checks

`zsh tools/test-rendering.sh` passes using SpriteKit in a logged-in graphics session:

- A red/blue source-view fixture stays a single source color through five turn-transition samples. It detects the old double-exposure blending path.
- Enlarged mid-turn captures cover all ten resident types. Bodies remain solid; fin transparency comes from the original artwork.
- Closely spaced frames straddle former pose boundaries, head-on views, and full-turn wraps for all ten resident types. The largest image change was 7.17%, normalized to visible pixel coverage, within the 8% regression threshold. These checks detect abrupt image switches; they do not establish perceptual smoothness at every frame rate.
- Each of the three scenes visibly changes with Plant sway enabled alone and Water movement enabled alone.
- Setting both controls to zero produces identical renders across time.
- Still mode produces identical renders after attempted advancement with atmosphere controls enabled.
- Bubble material captures show directional highlights and a clear center. Model tests additionally verify monotonically rising bubbles without position jumps at detachment.
- Pellet material captures show rounded cylinders, visible caps, directional shading, and near/far contrast. Production node checks confirm far bubbles and food pass behind fish and near particles pass in front.
- A production feeding capture stays identical in Still mode, including pellet orientation and depth effects.
- Stationary fish move their tails and balancing fins independently while their faces stay anchored. The controlled fin capture exercises the original four fish species through hovering, turning, and dashing. New checks verify motion at each of the crab’s eight walking feet, shrimp antenna motion, and rigid shells. Refuge occlusion progressively conceals shrimp while visible parts stay opaque.
- A grazing-turn regression checks that no detached fin copies appear beside the gourami.

These are rendering checks, not measurements of a physical display's pixel response or overdrive. The continuous fish surface removes pose-image switching while retaining the earlier removal of crossfade ghosting.

## Native application checks

The [release review report](docs/validation/release-report.json) records the following passing checks through the production renderer and control paths:

- All three scenes render with the default 26 fish and the final artwork. A separate colorful-community capture includes all ten species; settings captures cover small fish, larger fish, and shrimp/crab filters.
- Live → Still → Live works on-screen; Still renders zero animation frames during its measurement.
- Feeding produces 21 responders within two seconds and 8 consumed pellets during the 60-second observation.
- Manual Day/Night overrides and the AppKit appearance observer update the scene. Live lighting fades; appearance changes in Still preserve fish positions.
- Scene and population changes while still, desktop hide/show, and preview close/reopen work.
- PNG exports match the display's 3440×1440 resolution with the desktop aquarium enabled and disabled.
- The desktop window appears in WindowServer, sits below desktop icons, ignores mouse events, cannot become key, and is configured for all Spaces.
- Synthetic display sleep/wake notifications pause and resume rendering.

Another installed instance already owned the global feeding shortcut during the final run, so that run covered the registration-conflict fallback. An [earlier pre-release check](docs/validation/shortcut-pre-release-report.json) successfully registered, dispatched through the Carbon handler, unregistered, and re-registered the same shortcut implementation. These checks did not inject a physical key press while another app was active.

## Memory optimization comparison (1.0.3)

Two runs per version compared the tagged 1.0.2 renderer with 1.0.3 using the same [probe](Tests/PerformanceProbe.swift). Each scenario uses two visible production surfaces (1920×1080 and 960×540), three seconds of warmup, and six seconds of measurement. The table reports means; [all individual samples](docs/validation/performance-1.0.3.json) are retained.

| Scenario | Physical memory, MiB · 1.0.2 → 1.0.3 | CPU, % of one core · 1.0.2 → 1.0.3 | Measured fps · 1.0.2 → 1.0.3 |
| --- | --- | --- | --- |
| 26 fish, 30 fps setting | 197.1 → 137.8 | 12.04 → 12.41 | 26.42 → 27.95 |
| 120 fish, 30 fps setting | 198.9 → 139.9 | 20.57 → 21.76 | 26.34 → 29.18 |
| 120 fish, 60 fps setting | 179.7 → 145.1 | 37.38 → 33.12 | 54.05 → 57.34 |

Default-scene memory decreased about **30%**. Retained RGBA fish texture storage fell from **24.01 MiB to 3.79 MiB** (84%). Frame rates were higher on average. CPU use varied between runs and was slightly higher at the 30 fps setting, so this comparison does not establish a CPU reduction in every mode. Still rendered zero animation frames in all four runs. These short measurements do not establish sustained GPU power, thermal behavior, battery savings, or universal 60 fps performance.

## Previous movement update sample (1.0.4)

A single run of the same two-surface probe measured the new independent navigation. [Raw measurements](docs/validation/performance-1.0.4.json) are retained.

| Scenario | Physical memory, MiB | CPU, % of one core | Measured fps |
| --- | --- | --- | --- |
| 26 fish, 30 fps setting | 142.5 | 13.17 | 29.92 |
| 120 fish, 30 fps setting | 144.4 | 25.51 | 29.94 |
| 120 fish, 60 fps setting | 148.8 | 41.24 | 57.15 |

Still rendered zero animation frames. Memory remains below the 1.0.2 measurements; CPU in this sample was higher than the 1.0.3 means, particularly at maximum population. The added behavior does not establish a CPU improvement. These short runs are diagnostic samples, and the 60 fps setting is not a guarantee of sustained 60 fps.

## Current ten-species sample (1.1.0)

A single sequential run of the two-surface probe measured the new catalogue and behavior. Maximum scenarios now contain 12 of each of the ten resident types, including the larger koi and articulated crabs, so they are not population-equivalent comparisons with the older four-species maximum. [Raw measurements](docs/validation/performance-1.1.0.json) are retained.

| Scenario | Physical memory, MiB | CPU, % of one core | Measured fps |
| --- | --- | --- | --- |
| Default 26 fish, 30 fps setting | 147.7 | 12.31 | 29.25 |
| 120 mixed residents, 30 fps setting | 165.8 | 28.51 | 29.09 |
| 120 mixed residents, 60 fps setting | 165.8 | 51.62 | 53.32 |

Still rendered zero animation frames and used 0.57% of one CPU core in its short sample. All ten decoded resident textures together occupy 13.16 MiB of base RGBA storage and load only when used. The larger catalogue adds memory when its assets are selected; the shared 120-resident cap limits simulation growth. These short measurements do not establish sustained 60 fps or battery savings.

## Application review sample

The final review measured **29.99 fps** in the live preview, **9.06% of one CPU core** while live, and **0.78% of one core** while still, with **zero still animation frames**. Each mode was sampled for three seconds with a visible 1120×630 preview plus the production desktop window. These are diagnostic samples, not sustained GPU, thermal, or battery benchmarks.

## Images and limits

README scene images and the six-second GIF come from the production renderer. Settings captures use the production SwiftUI layout with a renderer snapshot substituted for the Metal layer, which AppKit's bitmap cache omits. Live animation is separately exercised on-screen. The GIF is sampled at 15 fps.

Finder icon dragging, Mission Control/Spaces switching, Stage Manager, physical display hotplug, real hardware sleep/wake, and applying a permanent native wallpaper have not been manually exercised. Appearance checks use this app's AppKit override; they do not change global macOS settings or wait for a scheduled sunset.

Two independent agent review loops were completed during development. Subsequent refinements were tested locally; no historical review score is presented as a rating of this final release. Fish use photographic material projected onto an articulated curved body and thin fins, rather than complete anatomical models; full three-dimensional schooling is future work.

The release app is ad-hoc signed, not Developer ID signed or Apple-notarized. See [installation](docs/INSTALL.md) for first-launch instructions.
