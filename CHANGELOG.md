# Changelog

## 2.0.1 — 2026-10-18

- **Bites you read from the float, not from a badge.** The orange halo and the "STRIKE NOW" pill are gone. A take now shows the way it does in clear water:
  - Small fish dip the float twice before it buries. Strike on the dips and the bait usually comes away; the Strike prompt, its tick, and the VoiceOver cue wait for the bury.
  - A loach, or any fish picking a bait up off the bottom, lifts the float so it keels over flat, and the line goes slack.
  - Bigger fish sail it away under, trailing behind them.
  - The bright collar where the tip breaks the film snaps shut, and broken, hand-drawn rings spread from the dent.
  - A dry fly goes in a dimpled sip as the fish noses up and turns down.
  - A sunk lure is hit with a flank flash, a line kick, and head-shakes.
- **A quieter readout.** The prompt is a plain "Strike, click or Space" line that fades as the fish's hold runs out. The fight readout loses its all-caps labels and badges, and the take messages read like an angler talking.

## 2.0.0 — 2026-10-18

- **Go fishing.** A new fishing window (fish menu → Go Fishing…, ⌘G in Stillwater, or Settings → Fishing) opens onto your aquarium with a rod in hand; the desktop aquarium is never disturbed. Click the water to cast there, click to strike, hold to reel, Esc to bring the line in.
- **Tackle that matters.** Three hooks: a No. 18 fine-wire hook for small mouths (light, so a strong fish can open it out), a No. 12 J-hook for gouramis, and a No. 6 circle hook for the koi that sets itself and almost never comes out. Three baits fished under a float at the depth you click (bloodworm, bread that crumbles away, soaked pellet) and three lures: a dry fly on the surface film, a micro spinner that only flashes while you reel, and a soft worm jig hopped along the sand.
- **Fish that behave like fish.** Bait reaches them by scent, lures by moving like prey. A fish swims over and looks it over, then refuses it, nibbles bits off the hook, or takes it, turning away while the float slides under (a danio barely dips it, a koi drags it right down). Small fish strip a big hook bare; shrimp and crabs steal bait off the sand and a crab may cling on as you reel. Followers trail a lure and hit it as it swims or falters. Splashes and fights scatter the shy ones while the bold ones come to look, and a fish that felt the hook stays wary, a little more after every catch.
- **A fight with real risk.** Small fish are swung straight out. Barbs and gouramis dive and shake their heads; horse one and the hook tears free. A koi runs and takes line through the drag: reel while it rests, let go when it runs, or the line snaps; let the line go slack and it throws the hook.
- **Readable on the water.** The float cocks upright as split shot settles the bait (and stays flat if a fish takes it on the drop), pecks ripple the film, an orange pulse marks the moment to strike, and a glow-stick tip lights the float at night. A tension meter with a RUN badge, a bait meter, plain-language messages, optional soft sounds, and VoiceOver announcements tell you what is happening.
- **Catch and release, and a log to fill.** Every fish is measured (each keeps its own size), weighed, shown on a catch card with personal bests and new species, and released. Settings → Fishing keeps a lifetime catch log for all eight hookable species, with field notes on what each one takes, and a tackle guide.
- Under the hood: the angling model is deterministic and fully tested (11 new model checks and a rendering check), and two new tools let scripted anglers fish every hook and bait headlessly (`tools/fishing-transcript.sh`) and render fishing moments for review (`tools/fishing-capture.sh`). CI runs the scripted anglers. Nothing changes in the desktop aquarium: without a line in the water, every fish makes exactly the same choices as before.

## 1.8.0 — 2026-10-17

- Saved wallpapers are retained until manually removed, protecting images still used by other Spaces or disconnected displays. Settings now shows how many stills are saved and how much space they take, with a button to open their folder, so they no longer accumulate invisibly.
- PNG and wallpaper exports preserve the current lighting during a day/night transition.
- Under the hood: the whole app now compiles in Swift 6 language mode with strict concurrency checking. Species-only behavior (shrimp, crab, loach) moved into a single enum payload so other fish no longer carry it, feeding and sand-bed logic split into their own simulation files, and crab gait constants are generated into the shader from the simulation instead of being matched by hand. Build scripts share one source list, the rendering tests explain themselves when run without a graphical session, and the performance probe reports budgets for frame rate, memory, and Still-mode CPU. No behavior changes are intended; the full model and rendering suites pass, with new checks for the stills summary and the generated shader constants.

## 1.7.0 — 2026-09-25

- Loaches keep a daily rhythm like real kuhli loaches: long rests (sometimes at the foot of a rock, sometimes lying alongside others), long unhurried stretches of foraging with the nose down in the sand, and now and then a brisker roam. Speeds are mixed: mostly still or slow, some steady swimming, and occasional quick darts, sometimes in playful zigzag bursts that a neighbour joins. Every rest has its own pose, curved or angled; the head stays down while foraging instead of flicking up; a loach never darts into the end of the bed or into a neighbour.
- Shrimp graze like cherry shrimp: the front claws pick at the sand in quick strokes while they stand, legs step exactly as far as they walk, antennae wave, and the swimmerets fan now and then at rest. A shrimp hides by walking behind a real rock in the scene and comes back out past its edge; a tail flip always drives it tail first, curling the abdomen under the body, and it settles back onto the sand afterwards. Shrimp no longer sparkle at desktop size, stand on loaches, or hide on open sand.
- Bubbles are small, slow, and look like beads of glass: a dark lower edge, a brighter middle, a silver rim and a glint, with the tiniest drawn as a speck and a point of light. Leaves grow a bead for several seconds before it lets go; bubbles slow as they reach the surface, meet their own mirrored reflection in the surface film, rest a moment and wink out. They rise at about 2–3 cm/s, far fewer of them, from spots on the sand and on real leaves in each scene.
## 1.6.0 — 2026-09-24

- Loaches keep their lanes on the sand: a loach never darts into a neighbour or a crab. Setting off with someone close ahead it turns back if there is room, or crawls diagonally across to another lane; a neighbour moving into its lane ends the dart and it coasts to a stop short of them. Loaches no longer pass through one another, stack, or line up nose to tail, and one boxed in by neighbours works its way free instead of parking.
- A loach and a crab keep a box of room between them, so a loach no longer lies with its snout across a crab's legs, and a darting loach gives crabs a wide berth.
- Crabs walking toward or away from you now stop or sidestep for whoever lies across their path instead of walking over them, and their stride in that direction is drawn foreshortened, so the legs no longer look like stilts.
- Loach darts are strongest at the start and ease off, with a top speed of about two body lengths a second; a loach that has just turned does not turn straight back again.

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
