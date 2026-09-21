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
