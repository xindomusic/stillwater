# Changelog

## 1.5.0 — 2026-09-24

- Crab legs now match the body's movement: the step cycle advances with the distance the crab actually travels, so planted feet no longer slide, whether it walks sideways, forward, back, or is nudged by a neighbour. When a crab stops, each lifted foot comes down where it is, and the shell bobs with each step while the feet stay put.
- Crabs walk in steadier bouts of a few steps, mostly carrying on the same way; when something is in the way they usually wait or sidestep rather than turning back. Their pace surges slightly with each step. A crab is not shoved along by loaches, crabs crowding food wait behind the one nearest it, and crabs leave the refuge edges to the shrimp.
- Loaches move like loaches instead of gliding at a constant speed: quick wriggling darts of one to three body lengths, strongest at the start, each veering a little, then pauses to sift. The body wave follows the distance travelled and beats two to three times a second in a dart, then fades as the loach coasts to a stop.
- A loach turns around by swimming round in a curve rather than spinning in place, and veers around neighbours and crabs ahead.
- A resting loach lies with its own slight curve and angle, eases its head down and pecks at the sand in irregular spells, and its tail ripples slowly.
- Loaches keep a little more room between each other, so two rarely read as one long fish.
- Fixed hidden shrimp being pushed out of their refuge by crabs.
- Bubbles are calm again: no air stones or streams, just the occasional single bubble drifting slowly up from the sand or a plant leaf, taking several seconds to reach the surface and swaying gently.
- The sand floor has perspective: bottom dwellers lower on the bed are nearer the glass and larger, those farther back sit higher and smaller, and turning on the sand carries them up or down the bed instead of in place.

## 1.4.0 — 2026-09-23

- Crab legs are now jointed limbs instead of a warped photograph: each of the eight legs has a raised knee and a foot that stays planted on the sand while the body moves, then lifts and steps forward, in the alternating diagonal gait of real crabs. The shell, eyes, and claws remain photographic, the legs are textured from the photographed legs, and a resting crab picks at the sand with its claws.
- Crabs keep a compact, low stance and stay clear of loaches, shrimp, and each other; the body bobs slightly with each step.
- Shrimp walking legs step in a wave from back to front, swimmerets beat while swimming, and legs tuck in off the sand. Grazing shrimp stay on the bed, and fleeing shrimp choose their own hiding spots.
- Loaches ripple along their whole length, tip only the head down into the sand when sifting, and rest on soft contact shadows that shorten when the fish faces you.
- Stirred sand shows as fine sand-coloured grains thrown up and settling back, with a soft silt cloud behind the animal that raised it.
- Wider sand beds in Sunken Grove and Willow Springs give bottom dwellers room.
- Fixed a torn loach head while sifting, leftover leg fragments on shrimp and crabs, and a fin-motion rendering check that depended on the display's pixel density.

## 1.3.0 — 2026-09-23

- Realistic bubbles: a dense air-stone stream of about 3 mm bubbles, a fainter one farther back, and tiny plant bubbles. Speeds follow measured rise rates; larger bubbles flatten, rock, and zigzag; each shows a clear inverted centre and a silvery rim, and distant ones soften.
- Food is now small, round, soaked micro-pellets with a wet sheen and individual tints, sinking nearly straight; distant pellets are smaller, bluer, and out of focus.
- Fish turn like fish: the body curves into the turn head first, then the tail sweeps back past straight and settles. Small fish flick round quickly with a deep bend; koi, gouramis, loaches, and bettas swing through wide arcs. The turn pivots near the front of the body, and a swung-out tail stays visible in the middle of a turn. Koi and gouramis cruise a little faster, closer to real fish.
- Bubble streams rise from small porous air stones bedded in the sand, releasing bubbles all along their length.
- Crabs and loaches lie side by side on the bed instead of piling on top of each other, and betta and gourami fins stay visible when the fish faces you.
- Residents stir the sand: loaches sifting, crabs setting off, shrimp picking, and fish taking food off the bottom kick up grains that settle, with a faint silt cloud.
- Shrimp escape in bursts of one to three tail flips, backward and upward, rising briefly above the bed.
- Fish no longer linger for minutes after eating before they can feed again.

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
