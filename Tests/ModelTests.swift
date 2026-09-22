import Foundation
import CoreGraphics

@main struct ModelTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    @MainActor static func main() throws {
        var config = AquariumConfiguration()
        require(config.totalFish == 26, "Default population should be 26 fish")
        config.setCount(.rasbora, -2)
        config.setCount(.cherry, 300)
        require(config.count(.rasbora) == 0 && config.count(.cherry) == 30, "Population limits")
        config.swimmingSpeed = .infinity; config.brightness = -20; config.plantSway = 50
        config.sanitize()
        require(config.swimmingSpeed == 0.5 && config.brightness == 0.4 && config.plantSway == 1, "Invalid saved settings must be sanitized")
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AquariumConfiguration.self, from: data)
        require(decoded == config, "Settings must round trip")

        config = AquariumConfiguration()
        var sim = AquariumSimulation()
        sim.synchronize(config)
        let firstIDs = sim.fish.filter { $0.species == .rasbora }.map(\.id)
        config.setCount(.rasbora, 14); sim.synchronize(config)
        require(Array(sim.fish.filter { $0.species == .rasbora }.map(\.id).prefix(12)) == firstIDs, "Adding fish must preserve current fish")
        config.setCount(.rasbora, 4); sim.synchronize(config)
        require(sim.fish.filter { $0.species == .rasbora }.map(\.id) == Array(firstIDs.prefix(4)), "Removing fish must preserve survivors")

        for theme in AquariumTheme.allCases {
            config.theme = theme; sim.synchronize(config)
            for _ in 0..<18000 { sim.step(delta: 1.0 / 30, configuration: config) }
            for fish in sim.fish {
                let r = AquariumSimulation.region(for: fish.species, theme: theme)
                require(fish.x.isFinite && fish.y.isFinite && fish.vx.isFinite && fish.vy.isFinite, "Simulation must stay finite")
                require((r.left...r.right).contains(fish.x) && (r.bottom...r.top).contains(fish.y), "Fish should stay in open-water bounds for \(theme)")
            }
        }
        let livePositions = sim.fish.map { [$0.x, $0.y] }
        for _ in 0..<30 { sim.step(delta: 1.0 / 30, configuration: config) }
        require(sim.fish.map { [$0.x, $0.y] } != livePositions, "Live mode should move fish")
        config.mode = .still
        let frozenPositions = sim.fish.map { [$0.x, $0.y] }
        let frozenTime = sim.time
        for _ in 0..<120 { sim.step(delta: 1.0 / 30, configuration: config) }
        require(sim.fish.map { [$0.x, $0.y] } == frozenPositions && sim.time == frozenTime, "Still mode must freeze fish AND water clock")
        config.mode = .live; config.swimmingSpeed = 0
        for _ in 0..<120 { sim.step(delta: 1.0 / 30, configuration: config) }
        require(sim.fish.map { [$0.x, $0.y] } == frozenPositions && sim.time > frozenTime, "Zero swim speed freezes fish but leaves atmosphere independent")
        for species in FishSpecies.allCases { config.setCount(species, 0) }
        sim.synchronize(config)
        require(sim.fish.isEmpty, "Just the plants means no fish")
        for species in FishSpecies.allCases { config.setCount(species, 30) }
        sim.synchronize(config)
        require(sim.fish.count == 120 && Set(sim.fish.map(\.id)).count == 120, "Maximum population must have unique identities")
        config.swimmingSpeed = 2
        for _ in 0..<120 { sim.step(delta: 10, configuration: config) }
        require(sim.fish.allSatisfy { $0.x.isFinite && $0.y.isFinite }, "Wake-up deltas must be bounded")
        for viewport in [CGSize(width: 1600, height: 900), CGSize(width: 3440, height: 1440), CGSize(width: 900, height: 1600)] {
            let framing = AquariumFraming(viewport: viewport, image: CGSize(width: 1935, height: 812))
            require(framing.imageRect.minY == 0, "The sand must stay anchored to the screen bottom")
            sim.visibleRegion = framing.visibleRegion
            for theme in AquariumTheme.allCases {
                config.theme = theme; sim.synchronize(config)
                for _ in 0..<120 { sim.step(delta: 1.0 / 30, configuration: config) }
                for fish in sim.fish {
                    let p = framing.point(x: fish.x, y: fish.y)
                    require(CGRect(origin: .zero, size: viewport).contains(p), "Fish and art must share a visible coordinate system on \(viewport)")
                    if fish.species == .loach { require(fish.y < 0.14, "Bottom dwellers must stay aligned with source-image sand") }
                }
            }
        }
        require(AquariumConfiguration().lightingMode == .system, "New aquariums follow macOS appearance")
        require(AquariumLighting.system.isNight(systemIsDark: true) && !AquariumLighting.system.isNight(systemIsDark: false), "Automatic lighting follows system dark/light")
        require(!AquariumLighting.day.isNight(systemIsDark: true) && AquariumLighting.night.isNight(systemIsDark: false), "Manual lighting overrides system")
        var savedObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AquariumConfiguration())) as! [String: Any]
        savedObject.removeValue(forKey: "lighting")
        savedObject["swimmingSpeed"] = 0.8
        let migrated = try JSONDecoder().decode(AquariumConfiguration.self, from: JSONSerialization.data(withJSONObject: savedObject))
        require(migrated.lightingMode == .system && migrated.swimmingSpeed == 0.8, "Older settings gain automatic lighting without resetting preferences")
        var manualLight = migrated; manualLight.lighting = .night
        let restoredLight = try JSONDecoder().decode(AquariumConfiguration.self, from: JSONEncoder().encode(manualLight))
        require(restoredLight == manualLight, "Manual lighting persists")
        var legacy = AquariumConfiguration()
        legacy.counts = ["cardinal": 3, "ember": 5, "gourami": 1, "cory": 2]
        legacy.sanitize()
        require(legacy.totalFish == 11 && legacy.count(.rasbora) == 3 && legacy.count(.loach) == 2, "Asian species must retain existing saved population choices")
        require(FishSpecies.allCases.filter(\.usesProfileAsset).allSatisfy { legacy.count($0) == 0 }, "Upgrades must not add new residents without a choice")
        var mixed = AquariumConfiguration()
        mixed.counts = Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map { ($0.rawValue, 12) })
        mixed.setCount(.crab, 30)
        require(mixed.totalFish == 120 && mixed.count(.crab) == 12, "Increasing a species at capacity must respect the shared limit")
        mixed.setCount(.rasbora, 0); mixed.setCount(.crab, 24)
        require(mixed.totalFish == 120 && mixed.count(.crab) == 24, "Removing residents must make room for another species")
        mixed.counts = Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map { ($0.rawValue, 30) })
        mixed.sanitize()
        require(mixed.totalFish == 120, "Oversized saved communities must remain within the renderer budget")
        mixed.counts = Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map { ($0.rawValue, 3) })
        mixed.swimmingSpeed = 2
        let savedMixed = try JSONDecoder().decode(AquariumConfiguration.self, from: JSONEncoder().encode(mixed))
        require(savedMixed == mixed, "All ten species counts must persist")
        var posture = AquariumSimulation(seed: 450)
        posture.synchronize(mixed)
        for theme in AquariumTheme.allCases {
            mixed.theme = theme; posture.synchronize(mixed)
            for frame in 0..<3600 {
                if frame % 900 == 0 { posture.feed(mixed) }
                let before = posture.fish
                posture.step(delta: 1.0 / 30, configuration: mixed)
                for (fish, previous) in zip(posture.fish, before) {
                    require(abs(fish.pitch) <= 0.220001, "Swimmers must never tip steeply backward or forward")
                    require(abs(fish.pitch - previous.pitch) < 0.04, "Posture changes must ease smoothly")
                    if fish.species.isInvertebrate {
                        require(fish.pitch == 0 && fish.spineCurve == .zero, "Invertebrate shells must stay level and rigid")
                        let region = AquariumSimulation.region(for: fish.species, theme: theme)
                        require((region.bottom...region.top).contains(fish.y), "Shrimp and crabs must remain on the substrate while feeding")
                    }
                    if fish.species == .crab {
                        require(abs(fish.yaw) < 0.65, "Crabs change body angle gently while crawling in different directions")
                        require(abs(fish.finPhase - previous.finPhase) < 0.7, "Crab gait reversals must keep all feet continuous")
                    }
                    let dx = fish.x - previous.x
                    let region = AquariumSimulation.region(for: fish.species, theme: theme)
                    if !fish.species.isInvertebrate && fish.x > region.left + 0.02 && fish.x < region.right - 0.02 {
                        require(dx * cos(fish.yaw) >= -0.000001, "A fish must turn its head before travelling backward across the screen")
                    }
                }
            }
        }
        print("PASS: ten-species persistence, bounded populations, upright smooth posture, forward swimming, and substrate residents")
        var bottomConfig = AquariumConfiguration()
        bottomConfig.counts = Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map { ($0.rawValue, $0.isInvertebrate ? 6 : 0) })
        bottomConfig.swimmingSpeed = 1
        for theme in AquariumTheme.allCases {
            bottomConfig.theme = theme
            var bottom = AquariumSimulation(seed: 1928); bottom.synchronize(bottomConfig)
            var phases = Set<ShrimpPhase>(), hidingIndividuals = Set<Int>(), directions: [Int: Set<Int>] = [:]
            var maximumHeight = 0.0
            for _ in 0..<18000 {
                bottom.step(delta: 1.0 / 30, configuration: bottomConfig)
                for resident in bottom.fish {
                    if resident.species == .shrimp {
                        let behavior = resident.shrimpBehavior
                        phases.insert(behavior.phase); maximumHeight = max(maximumHeight, resident.y)
                        if behavior.concealment > 0.9 {
                            hidingIndividuals.insert(resident.id)
                            require(hypot(resident.x - behavior.target.x, (resident.y - behavior.target.y) * 0.65) < 0.026, "Shrimp must reach a refuge before hiding")
                        }
                    }
                    if abs(resident.vx) > 0.0005 { directions[resident.id, default: []].insert(resident.vx < 0 ? 0 : 1) }
                    if abs(resident.vy) > 0.0005 { directions[resident.id, default: []].insert(resident.vy < 0 ? 2 : 3) }
                }
            }
            require(phases == Set(ShrimpPhase.allCases) && hidingIndividuals.count >= 3, "Shrimp must graze, drift, seek cover, hide and emerge independently in \(theme)")
            require(maximumHeight > AquariumSimulation.region(for: .loach, theme: theme).top + 0.03, "Shrimp should occasionally drift above the substrate")
            require(directions.values.filter { $0.count == 4 }.count >= 10, "Crabs and shrimp must explore left, right, forward and back")
            let frozen = bottom.fish.map { [$0.x, $0.y, $0.yaw, $0.finPhase, $0.shrimpBehavior.concealment, $0.shrimpBehavior.remaining] }
            var paused = bottomConfig; paused.mode = .still
            for _ in 0..<60 { bottom.step(delta: 1.0 / 30, configuration: paused) }
            require(frozen == bottom.fish.map { [$0.x, $0.y, $0.yaw, $0.finPhase, $0.shrimpBehavior.concealment, $0.shrimpBehavior.remaining] }, "Still must freeze shelter timers, crawling and concealment")
        }
        print("PASS: independent shrimp shelter cycles, varied drifting and crab crawl directions, and complete refuge freeze")
        var behavior = AquariumSimulation(seed: 12345)
        let natural = AquariumConfiguration()
        behavior.synchronize(natural)
        var moods = Set<FishMood>()
        var turns = 0
        var last = behavior.fish
        for _ in 0..<9000 {
            behavior.step(delta: 1.0 / 30, configuration: natural)
            for (f, before) in zip(behavior.fish, last) {
                moods.insert(f.mood)
                let turn = abs(AquariumSimulation.angleDifference(f.yaw, before.yaw))
                require(turn <= 1.8 / 60 + 0.000001, "Turns must be angularly continuous without an instant flip")
                require(abs(f.yawVelocity - before.yawVelocity) < 0.6, "Turning must accelerate and decelerate rather than snap to its speed limit")
                require(abs(f.activity - before.activity) < 0.15, "Moods must ease body activity rather than snap")
                require(f.finPhase > before.finPhase, "Hovering fish must still breathe and move their fins")
                if abs(cos(f.yaw)) < 0.25 { turns += 1 }
            }
            last = behavior.fish
        }
        require(moods.isSuperset(of: [.hover, .cruise, .dash, .forage]), "Individuals must exhibit all natural moods")
        require(turns > 10, "Turns must pass through front/rear angles")
        var wanderer = FishNavigation(seed: 231, heading: 0), repeatWanderer = FishNavigation(seed: 231, heading: 0)
        var otherWanderer = FishNavigation(seed: 902, heading: 0)
        let openWater = SwimRegion(left: 0, right: 1, bottom: 0, top: 1)
        var shortTurns = 0, wideTurns = 0, reversals = 0, leftTurns = 0, rightTurns = 0
        var paces: [Double] = [], turnRates: [Double] = [], intervals: [Double] = []
        for _ in 0..<36000 {
            let before = wanderer.decisions
            wanderer.advance(delta: 1.0 / 30, x: 0.5, y: 0.5, region: openWater, resting: false)
            // Consuming another individual's stream must not change this fish's choices.
            for _ in 0..<3 { otherWanderer.advance(delta: 1.0 / 30, x: 0.5, y: 0.5, region: openWater, resting: false) }
            repeatWanderer.advance(delta: 1.0 / 30, x: 0.5, y: 0.5, region: openWater, resting: false)
            require(wanderer.heading == repeatWanderer.heading && wanderer.remaining == repeatWanderer.remaining, "Fish navigation random streams must be independent")
            if wanderer.decisions != before {
                let angle = abs(wanderer.lastTurn)
                require(angle <= .pi, "An intention chooses a partial turn or reversal, never a full circle")
                if angle < .pi / 4 { shortTurns += 1 }
                else if angle < 2.4 { wideTurns += 1 }
                else { reversals += 1 }
                if wanderer.lastTurn < 0 { leftTurns += 1 } else { rightTurns += 1 }
                paces.append(wanderer.speedFactor); turnRates.append(wanderer.turnLimit); intervals.append(wanderer.remaining)
            }
        }
        require(shortTurns > wideTurns && wideTurns > reversals && reversals > 15, "Navigation must mix small changes, wider turns, and occasional reversals")
        require(leftTurns > 100 && rightTurns > 100, "Fish must turn in both directions")
        require(paces.max()! / paces.min()! > 2 && turnRates.max()! / turnRates.min()! > 2 && intervals.max()! / intervals.min()! > 3, "Fish need varied swimming speed, turning speed, and decision timing")
        let restingHeading = wanderer.heading
        for _ in 0..<300 { wanderer.advance(delta: 1.0 / 30, x: 0.5, y: 0.5, region: openWater, resting: true) }
        require(wanderer.heading == restingHeading, "Resting must hold an intention instead of repeatedly choosing turns")
        let frozenNavigation = behavior.fish.map { [$0.navigation.heading, $0.navigation.remaining, Double($0.navigation.decisions), $0.pitch] }
        var freezeNavigation = natural; freezeNavigation.mode = .still
        for _ in 0..<120 { behavior.step(delta: 1.0 / 30, configuration: freezeNavigation) }
        require(behavior.fish.map { [$0.navigation.heading, $0.navigation.remaining, Double($0.navigation.decisions), $0.pitch] } == frozenNavigation, "Still freezes navigation decisions and pitch")
        var bubbleTwin = AquariumSimulation(seed: 908), noBubbleTwin = AquariumSimulation(seed: 908)
        var withBubbles = natural; withBubbles.bubbles = true
        bubbleTwin.synchronize(withBubbles); noBubbleTwin.synchronize(natural)
        for _ in 0..<1800 { bubbleTwin.step(delta: 1.0 / 30, configuration: withBubbles); noBubbleTwin.step(delta: 1.0 / 30, configuration: natural) }
        require(bubbleTwin.fish.map { [$0.x,$0.y,$0.yaw] } == noBubbleTwin.fish.map { [$0.x,$0.y,$0.yaw] }, "Bubble randomness must not affect fish choices")
        require(Set(bubbleTwin.bubbles.map(\.randomState)).count == bubbleTwin.bubbles.count, "Every bubble must own its random stream")
        print("PASS: independent random navigation, partial turns and reversals, varied timing/speed, rest and Still freeze")
        // Hold speed constant to detect a short mechanical loop independent of mood changes.
        for species in FishSpecies.allCases {
            var stroke = FishStroke(seed: 91), twin = FishStroke(seed: 91), neighbor = FishStroke(seed: 193)
            var rates: [Double] = [], powers: [Double] = []
            var independentFrames = 0
            for frame in 0..<3600 {
                let before = stroke
                stroke.advance(delta: 1.0 / 60, species: species, speed: 0.85, acceleration: 0, turnRate: 0)
                twin.advance(delta: 1.0 / 60, species: species, speed: 0.85, acceleration: 0, turnRate: 0)
                neighbor.advance(delta: 1.0 / 60, species: species, speed: 0.85, acceleration: 0, turnRate: 0)
                require(stroke.amplitude == twin.amplitude && stroke.pectoralPhase == twin.pectoralPhase, "Motion must remain reproducible for a fixed seed")
                require(abs(stroke.amplitude - before.amplitude) < 0.055 && abs(stroke.tailRate - before.tailRate) < 0.45, "Random stroke changes must ease without a twitch")
                require(stroke.pectoralPhase > before.pectoralPhase && stroke.dorsalPhase > before.dorsalPhase, "Balancing fins must advance independently")
                if abs(stroke.amplitude - neighbor.amplitude) > 0.025 { independentFrames += 1 }
                if frame > 120 { rates.append(stroke.tailRate); powers.append(stroke.amplitude) }
            }
            require(rates.max()! / rates.min()! > 1.25 && powers.max()! / powers.min()! > 1.6, "Steady swimming must vary cadence and include softer glides for \(species)")
            require(independentFrames > 1800, "Neighboring fish must not share one stroke loop")
            var hover = FishStroke(seed: 9), dash = FishStroke(seed: 9)
            for _ in 0..<300 {
                hover.advance(delta: 1.0 / 60, species: species, speed: 0.03, acceleration: 0, turnRate: 0)
                dash.advance(delta: 1.0 / 60, species: species, speed: 2.5, acceleration: 0.5, turnRate: 0.7)
            }
            require(dash.amplitude > hover.amplitude * 4 && dash.tailRate > hover.tailRate * 2, "Dashing recruits stronger and faster tail strokes")
            require(hover.finAmplitude > 0.3 && hover.amplitude < 0.10, "Hovering keeps balancing fins alive while the tail rests")
        }
        let strokeSnapshot = behavior.fish.map { [$0.stroke.pectoralPhase, $0.stroke.dorsalPhase, $0.stroke.amplitude, $0.stroke.bend] }
        var stopped = natural; stopped.swimmingSpeed = 0
        for _ in 0..<120 { behavior.step(delta: 1.0 / 30, configuration: stopped) }
        require(behavior.fish.map { [$0.stroke.pectoralPhase, $0.stroke.dorsalPhase, $0.stroke.amplitude, $0.stroke.bend] } == strokeSnapshot, "Zero speed freezes all motor rhythms")
        stopped = natural; stopped.mode = .still
        for _ in 0..<120 { behavior.step(delta: 1.0 / 30, configuration: stopped) }
        require(behavior.fish.map { [$0.stroke.pectoralPhase, $0.stroke.dorsalPhase, $0.stroke.amplitude, $0.stroke.bend] } == strokeSnapshot, "Still freezes all motor rhythms")
        print("PASS: independent non-looping stroke variation, smooth transitions, glides, stronger dashes, and complete motor freeze")
        behavior.feed(natural)
        require(behavior.food.count + behavior.pendingFood.count == 12, "Feeding drops a small portion")
        var fedConfig = natural; fedConfig.mode = .still
        let pausedFood = behavior.food.map { [$0.x, $0.y, $0.age] }
        let pausedFish = behavior.fish.map { [$0.x, $0.y, $0.yaw, $0.finPhase, $0.activity] }
        behavior.feed(fedConfig)
        for _ in 0..<60 { behavior.step(delta: 1.0 / 30, configuration: fedConfig) }
        require(behavior.food.map { [$0.x, $0.y, $0.age] } == pausedFood && behavior.fish.map { [$0.x, $0.y, $0.yaw, $0.finPhase, $0.activity] } == pausedFish, "Still mode freezes food, turns, and fins and ignores feed requests")
        for _ in 0..<4800 { behavior.step(delta: 1.0 / 30, configuration: natural) }
        require(behavior.mealsEaten > 0, "Fish must actually reach and eat food")
        require(behavior.food.isEmpty, "Food must be eaten or expire")
        for _ in 0..<20 { behavior.feed(natural) }
        require(behavior.food.count + behavior.pendingFood.count == 36, "Repeated feeding must stay bounded")
        var changedScene = natural; changedScene.theme = .spring
        behavior.synchronize(changedScene)
        require(behavior.food.isEmpty && behavior.pendingFood.isEmpty, "Scene changes must clear old food")
        // User-visible acceptance: every species responds promptly, eats, and disperses.
        for theme in AquariumTheme.allCases {
            for species in FishSpecies.allCases {
                var feedingConfig = AquariumConfiguration(); feedingConfig.theme = theme
                for other in FishSpecies.allCases { feedingConfig.setCount(other, other == species ? 8 : 0) }
                var hungry = AquariumSimulation(seed: 12345); hungry.synchronize(feedingConfig)
                for _ in 0..<600 { hungry.step(delta: 1.0 / 30, configuration: feedingConfig) }
                hungry.feed(feedingConfig)
                var firstApproach: Double?
                var phases = Set<FeedingPhase>()
                var reactionTimes: [Int: Int] = [:]
                var leftUsualBand = false
                for frame in 0..<5400 {
                    hungry.step(delta: 1.0 / 30, configuration: feedingConfig)
                    for f in hungry.fish {
                        if let phase = f.feeding?.phase {
                            phases.insert(phase)
                            if phase == .approaching && reactionTimes[f.id] == nil {
                                reactionTimes[f.id] = frame
                                if firstApproach == nil { firstApproach = Double(frame) / 30 }
                            }
                        }
                        if f.y > AquariumSimulation.region(for: species, theme: theme).top { leftUsualBand = true }
                        require(f.x.isFinite && f.y.isFinite && f.y >= 0 && f.y <= 1, "Feeding stays in valid water coordinates")
                    }
                }
                require((firstApproach ?? 100) < 1.5, "\(species) must visibly respond within 1.5 seconds in \(theme)")
                require(phases.isSuperset(of: [.noticing, .approaching, .nibbling, .leaving]), "Feeding must include notice, approach, eating, and departure")
                require(Set(reactionTimes.values).count > 1, "Fish must react at different times")
                require(hungry.mealsEaten > 0 && hungry.food.isEmpty, "Every species must be able to eat and food must clear")
                require(hungry.fish.allSatisfy { $0.feeding == nil }, "\(species) must finish feeding and resume its own behavior in \(theme)")
                if species == .cherry { require(leftUsualBand, "Food above the normal swimming band must remain reachable") }
            }
        }
        var reacting = AquariumSimulation(); reacting.synchronize(natural); reacting.feed(natural)
        for _ in 0..<60 { reacting.step(delta: 1.0 / 30, configuration: natural) }
        let reactions = reacting.fish.map { $0.feeding?.age }
        var frozenFeeding = natural; frozenFeeding.mode = .still
        for _ in 0..<120 { reacting.step(delta: 1.0 / 30, configuration: frozenFeeding) }
        require(reacting.fish.map { $0.feeding?.age } == reactions, "Still mode freezes feeding response timers too")
        frozenFeeding.mode = .live; frozenFeeding.swimmingSpeed = 0
        for _ in 0..<120 { reacting.step(delta: 1.0 / 30, configuration: frozenFeeding) }
        require(reacting.fish.map { $0.feeding?.age } == reactions, "Zero swimming speed freezes feeding response timers")
        require(AquariumConfiguration().usesGlobalFeedingShortcut, "Global feeding shortcut is enabled by default")
        var shortcutConfig = AquariumConfiguration(); shortcutConfig.feedingShortcutEnabled = false
        let restoredShortcut = try JSONDecoder().decode(AquariumConfiguration.self, from: JSONEncoder().encode(shortcutConfig))
        require(!restoredShortcut.usesGlobalFeedingShortcut, "Global shortcut opt-out persists")
        var atmosphereConfig = AquariumConfiguration(); atmosphereConfig.bubbles = true
        atmosphereConfig.swimmingSpeed = 0
        var atmosphere = AquariumSimulation(); atmosphere.synchronize(atmosphereConfig)
        for _ in 0..<240 {
            let previous = atmosphere.bubbles
            atmosphere.step(delta: 1.0 / 60, configuration: atmosphereConfig)
            for (before, after) in zip(previous, atmosphere.bubbles) where before.generation == after.generation {
                require(after.y >= before.y, "Bubbles must rise monotonically")
                require(abs(after.x - before.x) < 0.0005, "Detachment and lateral bubble drift must remain continuous")
                require(after.y - before.y <= after.riseSpeed / 60 + 0.000001, "Bubble rise must not jump beyond its terminal speed")
            }
        }
        let origins = atmosphere.bubbles.map(\.originX)
        require(atmosphere.bubbles.contains { $0.depth < 0.7 } && atmosphere.bubbles.contains { $0.depth > 1.2 }, "Bubble population must include near and far water")
        for _ in 0..<3000 { atmosphere.step(delta: 1.0 / 30, configuration: atmosphereConfig) }
        require(atmosphere.bubbles.count == 14 && atmosphere.bubbles.allSatisfy { $0.generation > 0 }, "Bubbles must respawn independently of fish speed")
        require(zip(origins, atmosphere.bubbles).allSatisfy { abs($0 - $1.originX) > 0.001 }, "Bubble origins must change after respawn")
        require(Set(atmosphere.bubbles.map { Int($0.originX * 10) }).count > 4, "Bubble sources should cover several areas")
        let bubbleSnapshot = atmosphere.bubbles.map { [$0.x, $0.y, $0.age] }
        atmosphereConfig.mode = .still
        for _ in 0..<120 { atmosphere.step(delta: 1.0 / 30, configuration: atmosphereConfig) }
        require(atmosphere.bubbles.map { [$0.x, $0.y, $0.age] } == bubbleSnapshot, "Still mode freezes bubbles")
        var sprinkles = AquariumSimulation(); sprinkles.synchronize(natural); sprinkles.feed(natural)
        require(sprinkles.food.count == 1 && sprinkles.pendingFood.count == 11, "Food must arrive as staggered sprinkles")
        let portion = sprinkles.food + sprinkles.pendingFood
        require(portion.contains { $0.depth < 0.7 } && portion.contains { $0.depth > 1.2 }, "Each feeding portion must span near and far water")
        require(ParticlePerspective.scale(1.3) > ParticlePerspective.scale(0.65) * 2, "Distance must visibly change particle size")
        let orientations = portion.map { [Double($0.id), $0.tumble, $0.rotation, $0.depth] }
        require(Set(portion.map { Int($0.x * 100) }).count > 5, "Pellets must enter at different horizontal positions")
        require(Set(portion.map { $0.sinkSpeed }).count > 5 && Set(portion.map { $0.size }).count > 5, "Pellets need varied size and sinking speed")
        let queue = sprinkles.pendingFood.map(\.releaseDelay)
        var freezeSprinkles = natural; freezeSprinkles.mode = .still
        for _ in 0..<60 { sprinkles.step(delta: 1.0 / 30, configuration: freezeSprinkles) }
        require(sprinkles.pendingFood.map(\.releaseDelay) == queue, "Still mode freezes scheduled sprinkles")
        require((sprinkles.food + sprinkles.pendingFood).map { [Double($0.id), $0.tumble, $0.rotation, $0.depth] } == orientations, "Still mode freezes 3D pellet orientation and depth")
        for _ in 0..<45 { sprinkles.step(delta: 1.0 / 30, configuration: natural) }
        require(sprinkles.pendingFood.isEmpty, "The portion finishes dropping within 1.5 seconds")
        print("PASS: changing bubble origins, varied pellet sources/size/speed, staggered releases, and complete still freeze")
        print("PASS: all species react promptly in all scenes, stagger their response, eat and disperse; feeding freezes correctly; shortcut setting persists")
        print("PASS: smooth turns, all four natural moods, fin motion, feeding/consumption/limits, complete still freeze, and legacy population migration")
        print("PASS: settings, population reconciliation, 30 simulated minutes across three scenes, live/still, zero speed, maximum population, wake-up deltas")
    }
}
