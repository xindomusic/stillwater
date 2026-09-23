# Changelog

## 1.2.0 — 2026-09-22

- Fixed a hole through the middle of fish seen head-on during turns, and detached ghost copies during sharply bent turns. The body now marches through its bent volume to the first opaque point of the photograph, with fewer steps for side views.
- Replaced slow spins in place with banked U-turns: fish keep gliding while they turn, swing nearer or farther depending on which way has room, and climb along gentle slopes. A turn, once begun, is finished rather than abandoned. Wandering reversals take about one to two seconds at the default speed.
- Fish that spot food pivot toward it instead of drifting away, and turn faster while feeding (4.4 instead of 1.8 radians per movement unit).
- Every resident now rolls its own seeded dice (xoshiro256**), with realistic shapes of chance: random waits between decisions, mostly small course changes with occasional reversals, meandering paths, and a lasting temperament per fish.
- Large, slow fish swing through turns along an arc instead of pivoting, and fish swim along a slope when rising or diving to food instead of lifting straight up.
- Crabs scuttle sideways in quick stop-and-go bursts, with legs that rest when they stop. Shrimp pick their way in short steps and dart about two body lengths away from fish that hunt them, tail first when the threat is ahead.
- Old wallpaper stills are deleted when a new still is set, but only when no display uses them, they are over two weeks old, and they are not among the eight newest.
- Food choice no longer rescans the whole school for every pellet; a full-tank feeding frame simulates in well under a millisecond.
- Floating particles are sprites that batch into one GPU draw instead of CPU-tessellated shapes, and per-frame pellet and bubble shader values are reused instead of reallocated.
- Split the model into configuration, fish behavior, and simulation files, and the simulation step into named phases. Moved `--review` verification into its own file. Removed unused shader attributes.
- Model tests are named cases that all run and all report, with new checks for dice quality and distributions, irregular decision timing, meandering, lasting individual differences, crab and shrimp gaits, banked turns, real travel while head-on, finished turns, closing in on food, depth, climb slope, crowded-feeding speed, and still pruning. Added a rendering check for see-through head-on fish.

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
