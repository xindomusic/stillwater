# Changelog

## 1.0.4 — 2026-09-21

- Replaced shared looping routes with independent, irregular navigation choices: small course changes, wider turns, and occasional reversals.
- Varied each fish's swimming speed, turning speed, heading, and decision timing. Resting holds a heading, and turns take the shortest angular route.
- Added eased upward/downward posture and loose local gathering that leaves room for individual wandering.
- Isolated fish birth, navigation, mood/feeding, and fin random streams. Bubbles retain individual random states across respawns, and pellets receive their own seeded variations.
- Added checks for turn diversity, independent random streams, resting, and frozen navigation.

## 1.0.3 — 2026-09-21

- Added individual, smoothly varying tail strokes, glides, balancing fins, and stronger acceleration strokes.
- Made the head lead through eased turns while the body bends and the tail follows along a curved spine.
- Reduced retained fish textures to the profile actually displayed, shared the current scene texture, and reused per-fish shader values.
- Removed hidden-particle updates, full fish-state copies for separation, and temporary arrays during food selection.
- Added independent-fin and face-stability rendering checks, motor-variation tests, and a reproducible CPU/memory/frame-rate probe.

## 1.0.2 — 2026-09-21

- Added near, middle, and far distances for bubbles and food, with perspective size, water contrast, and correct overlap with fish.
- Replaced flat food ellipses with rounded, shaded 3D pellets that tumble and settle.
- Replaced fish view switching with continuous projection of a photographed body and thin fins, eliminating pose-boundary jumps.
- Added frame-continuity checks, particle-depth checks, and frozen 3D orientation checks.

## 1.0.1 — 2026-09-20

- Fixed double-image ghosting during turns: render one fish view at a time, with precomputed correspondence deformation and opaque bodies.
- Replaced flat bubble rings with clear, refractive centers and directional highlights; added smooth detachment and size-dependent rising speed.
- Made plant sway more visible with vegetation masks and anchored stems. Added surface ripples and drifting light on the riverbed.
- Renamed Water shimmer to Water movement without resetting existing preferences.
- Added native rendering regression checks for turn ghosting, independent atmosphere controls, and complete Still freezing.

## 1.0.0 — 2026-09-20

First public release. Includes the complete aquarium, settings, responsive feeding, automatic day/night lighting, randomized bubble lifecycles, and varied pellet sprinkles described in the [release notes](docs/releases/v1.0.0.md).

Earlier local development version labels were not public releases. The public version sequence begins at 1.0.0.
