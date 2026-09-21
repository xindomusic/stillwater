# Stillwater 1.0.0 validation

Validated September 20, 2026 on an Apple M4, macOS 27.0, with one 3440×1440 display. The app targets Apple Silicon and macOS 14+. Older supported macOS versions have not been tested locally.

## Automated model checks

`zsh tools/test.sh` passes. Coverage includes:

- Saved configuration, migration, sanitization, population limits, and stable fish identities.
- Thirty simulated minutes across scenes, 120-fish populations, bounded wake-up deltas, and standard, ultrawide, and portrait framing.
- Continuous turns, eased activity, hovering, cruising, dashing, foraging, and fin motion.
- All four species in all three scenes reacting to feeding within 1.5 seconds; approach, consumption, departure, and abandonment of unreachable food.
- Staggered pellet releases from varied locations, different sizes and sinking speeds, portion limits, expiry, and scene-change cleanup.
- Bubble origins changing on respawn, distribution across the water, and bubble movement independent of fish swimming speed.
- Complete Still freezing of fish, fins, turns, reaction timers, visible and pending food, and bubbles.

## Native application checks

The [release review report](docs/validation/release-report.json) records the following passing checks through the production renderer and control paths:

- All three scenes render with 26 fish and the final artwork.
- Live → Still → Live works on-screen; Still renders zero animation frames during its measurement.
- Feeding produces 21 responders within two seconds and 10 consumed pellets during the 60-second observation.
- Manual Day/Night overrides and the AppKit appearance observer update the scene. Live lighting fades; appearance changes in Still preserve fish positions.
- Scene and population changes while still, desktop hide/show, and preview close/reopen work.
- PNG exports match the display's 3440×1440 resolution with the desktop aquarium enabled and disabled.
- The desktop window appears in WindowServer, sits below desktop icons, ignores mouse events, cannot become key, and is configured for all Spaces.
- Synthetic display sleep/wake notifications pause and resume rendering.

A development instance already owned the global feeding shortcut during the final run, so that run covered the registration-conflict fallback. An [earlier pre-release check](docs/validation/shortcut-pre-release-report.json) successfully registered, dispatched through the Carbon handler, unregistered, and re-registered the same shortcut implementation. These checks did not inject a physical key press while another app was active.

## Short performance sample

The final review measured **28.27 fps** in the live preview, **13.38% of one CPU core** while live, and **0.61% of one core** while still, with **zero still animation frames**. Each mode was sampled for three seconds with a visible 1120×630 preview plus the production desktop window. These are diagnostic samples, not sustained GPU, thermal, or battery benchmarks.

## Images and limits

README scene images and the six-second GIF come from the production renderer. Settings captures use the production SwiftUI layout with a renderer snapshot substituted for the Metal layer, which AppKit's bitmap cache omits. Live animation is separately exercised on-screen. The GIF is sampled at 15 fps.

Finder icon dragging, Mission Control/Spaces switching, Stage Manager, physical display hotplug, real hardware sleep/wake, and applying a permanent native wallpaper have not been manually exercised. Appearance checks use this app's AppKit override; they do not change global macOS settings or wait for a scheduled sunset.

Two independent agent review loops were completed during development. Subsequent refinements were tested locally; no historical review score is presented as a rating of this final release. Fish remain layered 2D artwork with procedural motion; richer general schooling is future work.

The release app is ad-hoc signed, not Developer ID signed or Apple-notarized. See [installation](docs/INSTALL.md) for first-launch instructions.
