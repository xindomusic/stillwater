import Foundation
import CoreGraphics

/// A small dependency-free test runner: every case runs, every failure is reported.
@MainActor final class TestRun {
    private(set) var failures: [String] = []
    private var current = ""

    func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { failures.append("\(current): \(message)") }
    }

    func test(_ name: String, _ body: () throws -> Void) {
        current = name
        let before = failures.count
        let start = Date()
        do { try body() } catch { failures.append("\(name): threw \(error)") }
        let seconds = String(format: "%.2fs", Date().timeIntervalSince(start))
        print(failures.count == before ? "PASS \(name) (\(seconds))" : "FAIL \(name)")
    }
}

private let frame = 1.0 / 30

private func run(_ sim: inout AquariumSimulation, frames: Int, _ configuration: AquariumConfiguration, delta: Double = frame) {
    for _ in 0..<frames { sim.step(delta: delta, configuration: configuration) }
}

private func population(_ counts: [FishSpecies: Int]) -> AquariumConfiguration {
    var config = AquariumConfiguration()
    config.counts = Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map { ($0.rawValue, counts[$0] ?? 0) })
    return config
}

@main struct ModelTests {
    @MainActor static func main() throws {
        let t = TestRun()
        diceTests(t)
        settingsTests(t)
        populationTests(t)
        boundsAndFreezeTests(t)
        postureTests(t)
        turningTests(t)
        individualityTests(t)
        bottomDwellerTests(t)
        crabAndShrimpGaitTests(t)
        navigationTests(t)
        strokeTests(t)
        feedingTests(t)
        atmosphereTests(t)
        wallpaperStillTests(t)
        if t.failures.isEmpty { print("All model tests passed") }
        else { t.failures.forEach { fputs("FAIL: \($0)\n", stderr) }; exit(1) }
    }

    // MARK: Dice

    @MainActor static func diceTests(_ t: TestRun) {
        t.test("the dice is reproducible, uniform, and independent between seeds") {
            var a = Dice(seed: 7), b = Dice(seed: 7), c = Dice(seed: 8)
            let first = (0..<1000).map { _ in a.next() }
            t.check(first == (0..<1000).map { _ in b.next() }, "The same seed replays the same rolls")
            let neighbor = (0..<1000).map { _ in c.next() }
            let mean = first.reduce(0, +) / 1000, neighborMean = neighbor.reduce(0, +) / 1000
            let covariance = zip(first, neighbor).map { ($0 - mean) * ($1 - neighborMean) }.reduce(0, +) / 1000
            t.check(abs(covariance / (1.0 / 12)) < 0.1, "Neighbouring seeds must give unrelated streams")
            // Reference outputs of xoshiro256** seeded through SplitMix64 (Vigna's C code), seed 42017.
            var reference = Dice(seed: 42017)
            let expected: [UInt64] = [8723177749431103710, 13250387317515289512, 16639807300470105580, 14371798324951300031, 14124627334371994339]
            t.check((0..<5).map { _ in reference.nextBits() } == expected, "The generator matches the published xoshiro256** algorithm")
            var dice = Dice(seed: 2026)
            var bins = [Int](repeating: 0, count: 10)
            for _ in 0..<100_000 { let roll = dice.next(); t.check(roll >= 0 && roll < 1, "Rolls stay in [0, 1)"); bins[Int(roll * 10)] += 1 }
            t.check(bins.allSatisfy { abs($0 - 10_000) < 500 }, "Every tenth of the range comes up equally often (\(bins))")
        }
        t.test("the dice shapes normal, exponential, and log-normal draws") {
            var dice = Dice(seed: 99)
            let normals = (0..<50_000).map { _ in dice.normal(mean: 2, deviation: 0.5) }
            let normalMean = normals.reduce(0, +) / Double(normals.count)
            let normalDeviation = sqrt(normals.map { ($0 - normalMean) * ($0 - normalMean) }.reduce(0, +) / Double(normals.count))
            t.check(abs(normalMean - 2) < 0.01 && abs(normalDeviation - 0.5) < 0.01, "Normal draws have the requested mean and spread")
            let withinOne = Double(normals.filter { abs($0 - 2) < 0.5 }.count) / Double(normals.count)
            t.check(abs(withinOne - 0.683) < 0.01, "About 68% of normal draws fall within one deviation")
            let waits = (0..<50_000).map { _ in dice.exponential(mean: 3) }
            t.check(abs(waits.reduce(0, +) / Double(waits.count) - 3) < 0.06, "Exponential waits have the requested mean")
            let longWaits = Double(waits.filter { $0 > 3 }.count) / Double(waits.count)
            t.check(abs(longWaits - exp(-1)) < 0.01, "About 37% of exponential waits outlast the mean")
            let skewed = (0..<50_000).map { _ in dice.logNormal(median: 1.5, spread: 0.3) }.sorted()
            t.check(abs(skewed[skewed.count / 2] - 1.5) < 0.02 && skewed.allSatisfy { $0 > 0 }, "Log-normal draws are positive around their median")
        }
    }

    // MARK: Settings

    @MainActor static func settingsTests(_ t: TestRun) {
        t.test("settings are bounded, sanitized, and round trip") {
            var config = AquariumConfiguration()
            t.check(config.totalFish == 26, "Default population should be 26 fish")
            config.setCount(.rasbora, -2)
            config.setCount(.cherry, 300)
            t.check(config.count(.rasbora) == 0 && config.count(.cherry) == 30, "Population limits")
            config.swimmingSpeed = .infinity; config.brightness = -20; config.plantSway = 50
            config.sanitize()
            t.check(config.swimmingSpeed == 0.5 && config.brightness == 0.4 && config.plantSway == 1, "Invalid saved settings must be sanitized")
            let decoded = try JSONDecoder().decode(AquariumConfiguration.self, from: JSONEncoder().encode(config))
            t.check(decoded == config, "Settings must round trip")
        }
        t.test("lighting follows macOS and older settings migrate") {
            t.check(AquariumConfiguration().lightingMode == .system, "New aquariums follow macOS appearance")
            t.check(AquariumLighting.system.isNight(systemIsDark: true) && !AquariumLighting.system.isNight(systemIsDark: false), "Automatic lighting follows system dark/light")
            t.check(!AquariumLighting.day.isNight(systemIsDark: true) && AquariumLighting.night.isNight(systemIsDark: false), "Manual lighting overrides system")
            var saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AquariumConfiguration())) as! [String: Any]
            saved.removeValue(forKey: "lighting")
            saved["swimmingSpeed"] = 0.8
            let migrated = try JSONDecoder().decode(AquariumConfiguration.self, from: JSONSerialization.data(withJSONObject: saved))
            t.check(migrated.lightingMode == .system && migrated.swimmingSpeed == 0.8, "Older settings gain automatic lighting without resetting preferences")
            var manual = migrated; manual.lighting = .night
            let restoredLight = try JSONDecoder().decode(AquariumConfiguration.self, from: JSONEncoder().encode(manual))
            t.check(restoredLight == manual, "Manual lighting persists")
            t.check(AquariumConfiguration().usesGlobalFeedingShortcut, "Global feeding shortcut is enabled by default")
            var shortcut = AquariumConfiguration(); shortcut.feedingShortcutEnabled = false
            let restored = try JSONDecoder().decode(AquariumConfiguration.self, from: JSONEncoder().encode(shortcut))
            t.check(!restored.usesGlobalFeedingShortcut, "Global shortcut opt-out persists")
        }
        t.test("legacy and mixed populations respect the shared limit") {
            var legacy = AquariumConfiguration()
            legacy.counts = ["cardinal": 3, "ember": 5, "gourami": 1, "cory": 2]
            legacy.sanitize()
            t.check(legacy.totalFish == 11 && legacy.count(.rasbora) == 3 && legacy.count(.loach) == 2, "Asian species must retain existing saved population choices")
            t.check(FishSpecies.allCases.filter(\.usesProfileAsset).allSatisfy { legacy.count($0) == 0 }, "Upgrades must not add new residents without a choice")
            var mixed = population(Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map { ($0, 12) }))
            mixed.setCount(.crab, 30)
            t.check(mixed.totalFish == 120 && mixed.count(.crab) == 12, "Increasing a species at capacity must respect the shared limit")
            mixed.setCount(.rasbora, 0); mixed.setCount(.crab, 24)
            t.check(mixed.totalFish == 120 && mixed.count(.crab) == 24, "Removing residents must make room for another species")
            mixed = population(Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map { ($0, 30) }))
            mixed.sanitize()
            t.check(mixed.totalFish == 120, "Oversized saved communities must remain within the renderer budget")
            mixed = population(Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map { ($0, 3) }))
            let savedMixed = try JSONDecoder().decode(AquariumConfiguration.self, from: JSONEncoder().encode(mixed))
            t.check(savedMixed == mixed, "All ten species counts must persist")
        }
    }

    // MARK: Population

    @MainActor static func populationTests(_ t: TestRun) {
        t.test("adding and removing fish preserves individuals") {
            var config = AquariumConfiguration()
            var sim = AquariumSimulation()
            sim.synchronize(config)
            let firstIDs = sim.fish.filter { $0.species == .rasbora }.map(\.id)
            config.setCount(.rasbora, 14); sim.synchronize(config)
            t.check(Array(sim.fish.filter { $0.species == .rasbora }.map(\.id).prefix(12)) == firstIDs, "Adding fish must preserve current fish")
            config.setCount(.rasbora, 4); sim.synchronize(config)
            t.check(sim.fish.filter { $0.species == .rasbora }.map(\.id) == Array(firstIDs.prefix(4)), "Removing fish must preserve survivors")
            for species in FishSpecies.allCases { config.setCount(species, 0) }
            sim.synchronize(config)
            t.check(sim.fish.isEmpty, "Just the plants means no fish")
            for species in FishSpecies.allCases { config.setCount(species, 30) }
            sim.synchronize(config)
            t.check(sim.fish.count == 120 && Set(sim.fish.map(\.id)).count == 120, "Maximum population must have unique identities")
        }
    }

    // MARK: Bounds and freezing

    @MainActor static func boundsAndFreezeTests(_ t: TestRun) {
        t.test("30 simulated minutes stay in bounds; Still and zero speed freeze") {
            var config = AquariumConfiguration()
            var sim = AquariumSimulation()
            for theme in AquariumTheme.allCases {
                config.theme = theme; sim.synchronize(config)
                run(&sim, frames: 18000, config)
                for fish in sim.fish {
                    let r = AquariumSimulation.region(for: fish.species, theme: theme)
                    t.check(fish.x.isFinite && fish.y.isFinite && fish.vx.isFinite && fish.vy.isFinite, "Simulation must stay finite")
                    let headroom = fish.species == .shrimp ? AquariumSimulation.escapeHeadroom : 0
                    t.check((r.left...r.right).contains(fish.x) && (r.bottom...(r.top + headroom)).contains(fish.y), "Fish should stay in open-water bounds for \(theme)")
                    t.check(FishState.depthRange.contains(fish.depth), "Depth must stay inside the band particles layer against")
                }
            }
            let live = sim.fish.map { [$0.x, $0.y] }
            run(&sim, frames: 30, config)
            t.check(sim.fish.map { [$0.x, $0.y] } != live, "Live mode should move fish")
            config.mode = .still
            let frozen = sim.fish.map { [$0.x, $0.y] }, frozenTime = sim.time
            run(&sim, frames: 120, config)
            t.check(sim.fish.map { [$0.x, $0.y] } == frozen && sim.time == frozenTime, "Still mode must freeze fish AND water clock")
            config.mode = .live; config.swimmingSpeed = 0
            run(&sim, frames: 120, config)
            t.check(sim.fish.map { [$0.x, $0.y] } == frozen && sim.time > frozenTime, "Zero swim speed freezes fish but leaves atmosphere independent")
            for species in FishSpecies.allCases { config.setCount(species, 30) }
            sim.synchronize(config)
            config.swimmingSpeed = 2
            run(&sim, frames: 120, config, delta: 10)
            t.check(sim.fish.allSatisfy { $0.x.isFinite && $0.y.isFinite }, "Wake-up deltas must be bounded")
        }
        t.test("fish and art share coordinates on every display shape") {
            var config = AquariumConfiguration()
            for species in FishSpecies.allCases { config.setCount(species, 12) }
            var sim = AquariumSimulation()
            for viewport in [CGSize(width: 1600, height: 900), CGSize(width: 3440, height: 1440), CGSize(width: 900, height: 1600)] {
                let framing = AquariumFraming(viewport: viewport, image: CGSize(width: 1935, height: 812))
                t.check(framing.imageRect.minY == 0, "The sand must stay anchored to the screen bottom")
                sim.visibleRegion = framing.visibleRegion
                for theme in AquariumTheme.allCases {
                    config.theme = theme; sim.synchronize(config)
                    run(&sim, frames: 120, config)
                    for fish in sim.fish {
                        t.check(CGRect(origin: .zero, size: viewport).contains(framing.point(x: fish.x, y: fish.y)), "Fish and art must share a visible coordinate system on \(viewport)")
                        if fish.species == .loach { t.check(fish.y < 0.14, "Bottom dwellers must stay aligned with source-image sand") }
                    }
                }
            }
        }
    }

    // MARK: Posture

    @MainActor static func postureTests(_ t: TestRun) {
        t.test("upright smooth posture, forward swimming, and substrate residents") {
            var mixed = population(Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map { ($0, 3) }))
            mixed.swimmingSpeed = 2
            var sim = AquariumSimulation(seed: 450)
            for theme in AquariumTheme.allCases {
                mixed.theme = theme; sim.synchronize(mixed)
                for step in 0..<3600 {
                    if step % 900 == 0 { sim.feed(mixed) }
                    let before = sim.fish
                    sim.step(delta: frame, configuration: mixed)
                    for (fish, previous) in zip(sim.fish, before) {
                        t.check(abs(fish.pitch) <= 0.450001, "Swimmers must never tip steeply backward or forward")
                        if !fish.isChasingFood && abs(fish.pitch) > 0.220001 {
                            t.check(abs(fish.pitch) < abs(previous.pitch), "After a strike at food a fish levels out toward its usual gentle attitude")
                        }
                        t.check(abs(fish.pitch - previous.pitch) < 0.04, "Posture changes must ease smoothly")
                        let region = AquariumSimulation.region(for: fish.species, theme: theme)
                        if fish.species.isInvertebrate {
                            t.check(fish.pitch == 0 && fish.spineCurve == .zero, "Invertebrate shells must stay level and rigid")
                            let headroom = fish.species == .shrimp ? AquariumSimulation.escapeHeadroom : 0
                            t.check((region.bottom...(region.top + headroom)).contains(fish.y), "Shrimp and crabs stay on or just above the substrate")
                        }
                        if fish.species == .crab {
                            t.check(abs(fish.yaw) < 0.65, "Crabs change body angle gently while crawling in different directions")
                            t.check(abs(fish.finPhase - previous.finPhase) < 0.7, "Crab gait reversals must keep all feet continuous")
                        }
                        // Loaches can be nudged sideways by a neighbour on the bed, so only mid-water fish are checked.
                        if !fish.species.isBottomDweller && fish.x > region.left + 0.02 && fish.x < region.right - 0.02 {
                            t.check((fish.x - previous.x) * cos(fish.yaw) >= -0.000001, "A fish must never travel tail-first across the screen")
                        }
                    }
                }
            }
        }
    }

    // MARK: Turning

    @MainActor static func turningTests(_ t: TestRun) {
        t.test("turns are continuous, eased, and pass through front and rear views") {
            var sim = AquariumSimulation(seed: 12345)
            let natural = AquariumConfiguration()
            sim.synchronize(natural)
            var moods = Set<FishMood>(), sideOnFrames = 0
            var last = sim.fish
            for _ in 0..<9000 {
                sim.step(delta: frame, configuration: natural)
                for (f, before) in zip(sim.fish, last) {
                    moods.insert(f.mood)
                    let turn = abs(AquariumSimulation.angleDifference(f.yaw, before.yaw))
                    let movement = frame * natural.swimmingSpeed
                    let agility = FishSpecies.allCases.map(\.turnAgility).max()!
                    let fastestTurn = max(AquariumSimulation.feedingTurnLimit, FishNavigation.turnLimits.upperBound) * agility
                    t.check(turn <= fastestTurn * movement + 0.000001, "Turns must be angularly continuous without an instant flip")
                    t.check(abs(f.yawVelocity - before.yawVelocity) < 1.1, "Turning must accelerate and decelerate rather than snap to its speed limit")
                    t.check(abs(f.activity - before.activity) < 0.15, "Moods must ease body activity rather than snap")
                    t.check(f.finPhase > before.finPhase, "Hovering fish must still breathe and move their fins")
                    t.check(abs(f.depth - before.depth) < 0.01, "Depth must change gradually")
                    if abs(cos(f.yaw)) < 0.25 { sideOnFrames += 1 }
                }
                last = sim.fish
            }
            t.check(moods.isSuperset(of: [.hover, .cruise, .dash, .forage]), "Individuals must exhibit all natural moods")
            t.check(sideOnFrames > 10, "Turns must pass through front/rear angles")
        }
        t.test("turns have two stages: the body curves in, then the tail flips back") {
            var config = population([.rasbora: 8, .koi: 3, .pearl: 3, .loach: 4])
            config.theme = .river
            config.swimmingSpeed = 0.72
            var sim = AquariumSimulation(seed: 64); sim.synchronize(config)
            var peakBend: [Int: Double] = [:], watching: [Int: (sign: Double, frames: Int)] = [:]
            var turns = 0, flipBacks = 0
            var halfTurnSeconds: [FishSpecies: [Double]] = [:], turnStart: [Int: Int] = [:]
            for step in 0..<18_000 {
                let before = sim.fish
                sim.step(delta: frame, configuration: config)
                for (f, previous) in zip(sim.fish, before) where f.feeding == nil {
                    if f.turnDirection != 0 { peakBend[f.id] = abs(f.stroke.bend) > abs(peakBend[f.id] ?? 0) ? f.stroke.bend : peakBend[f.id] }
                    if previous.turnDirection != 0 && f.turnDirection == 0, let peak = peakBend[f.id], abs(peak) > 0.2 {
                        watching[f.id] = (peak > 0 ? 1 : -1, 0); peakBend[f.id] = nil; turns += 1
                    }
                    if let watch = watching[f.id] {
                        if f.stroke.bend * watch.sign < -0.15 { flipBacks += 1; watching[f.id] = nil }
                        else if watch.frames > 30 { watching[f.id] = nil }
                        else { watching[f.id] = (watch.sign, watch.frames + 1) }
                    }
                    if abs(cos(previous.yaw)) > 0.95 && abs(cos(f.yaw)) <= 0.95 { turnStart[f.id] = step }
                    if cos(f.yaw) * cos(previous.yaw) < 0, let start = turnStart[f.id] {
                        halfTurnSeconds[f.species, default: []].append(Double(step - start) * frame); turnStart[f.id] = nil
                    }
                }
            }
            t.check(turns > 30 && Double(flipBacks) / Double(turns) > 0.6, "After a turn the tail flips back past straight (\(flipBacks) of \(turns) turns)")
            let median = { (s: FishSpecies) -> Double in let v = halfTurnSeconds[s]!.sorted(); return v[v.count / 2] }
            t.check(median(.rasbora) * 2 < median(.koi), "Small fish flick round far faster than koi (\(median(.rasbora)) s vs \(median(.koi)) s for half a turn)")
        }
        t.test("hovering gouramis and bettas turn on their fins, and nobody sprints through a turn") {
            var config = population([.pearl: 4, .betta: 4, .koi: 3, .rasbora: 6])
            config.theme = .river
            var sim = AquariumSimulation(seed: 19); sim.synchronize(config)
            var hoverTurnFrames = 0, turnStartSpeed: [Int: Double] = [:], hovering: [Int: Int] = [:]
            for _ in 0..<18_000 {
                let before = sim.fish
                sim.step(delta: frame, configuration: config)
                for (f, previous) in zip(sim.fish, before) where f.feeding == nil && !f.species.isInvertebrate {
                    hovering[f.id] = f.isHovering ? (hovering[f.id] ?? 0) + 1 : 0
                    // Once settled into a hover (the body straightens within a moment of arriving).
                    if hovering[f.id]! > 40 && abs(f.yawVelocity) > 0.3 {
                        hoverTurnFrames += 1
                        t.check(abs(f.stroke.bend) < 0.25, "A hovering \(f.species) turns with a nearly straight body (bend \(f.stroke.bend))")
                    }
                    if f.turnDirection != 0 && previous.turnDirection == 0 { turnStartSpeed[f.id] = f.forwardSpeed }
                    if f.turnDirection == 0 { turnStartSpeed[f.id] = nil }
                    if let start = turnStartSpeed[f.id] {
                        // Its own cruising pace, or a modest push through the turn, whichever is faster.
                        let ownPace = f.species.cruiseSpeed * f.navigation.speedFactor * f.personality.boldness * max(1, f.activity)
                        let allowed = max(start, ownPace, f.species.cruiseSpeed * AquariumSimulation.turnSurge) * 1.05
                        t.check(f.forwardSpeed <= allowed, "\(f.species) does not sprint to make a turn (\(f.forwardSpeed) vs \(allowed))")
                    }
                }
            }
            t.check(hoverTurnFrames > 50, "Gouramis and bettas do turn while hovering (\(hoverTurnFrames) frames)")
        }
        t.test("large and slow fish swim through their turns") {
            var config = population([.loach: 6, .pearl: 3, .betta: 3, .koi: 3])
            config.theme = .river
            var sim = AquariumSimulation(seed: 88); sim.synchronize(config)
            var turnStart: [Int: (x: Double, y: Double, depth: Double)] = [:], paths: [FishSpecies: [Double]] = [:]
            for _ in 0..<36_000 {
                let before = sim.fish
                sim.step(delta: frame, configuration: config)
                for (f, previous) in zip(sim.fish, before) where f.feeding == nil {
                    if abs(cos(previous.yaw)) > 0.7 && abs(cos(f.yaw)) <= 0.7 { turnStart[f.id] = (f.x, f.y, f.depth) }
                    // Crossing the head-on view completes the first half of a reversal.
                    if cos(f.yaw) * cos(previous.yaw) < 0, let start = turnStart[f.id] {
                        let travel = hypot(hypot(f.x - start.x, f.y - start.y), (f.depth - start.depth) / AquariumSimulation.depthTravel)
                        paths[f.species, default: []].append(travel / f.species.bodyLength)
                        turnStart[f.id] = nil
                    }
                }
            }
            for (species, lengths) in paths {
                let sorted = lengths.sorted()
                t.check(sorted.count > 10 && sorted[sorted.count / 2] > 0.12, "\(species) travels during the first half of a turn instead of pivoting (median \(String(format: "%.2f", sorted[sorted.count / 2])) body lengths)")
            }
        }
        t.test("U-turns glide along an arc instead of spinning in place") {
            var config = population([.rasbora: 10, .golden: 6, .koi: 3, .betta: 3])
            config.theme = .river
            let movement = frame * config.swimmingSpeed
            var sim = AquariumSimulation(seed: 77)
            sim.synchronize(config)
            var headOnFrames = 0, wanderingHeadOnFrames = 0, movingHeadOnFrames = 0, totalFrames = 0, longestHeadOn = 0
            var headOnRun: [Int: Int] = [:], leftHome = Set<Int>()
            var lastFlip: [Int: Int] = [:], flips = 0, quickFlipBacks = 0, feedingFlips = 0, quickFeedingFlipBacks = 0
            var sweep: [Int: Double] = [:], longestSweep = 0.0
            for step in 0..<18000 {
                if step % 1800 == 0 { sim.feed(config) }
                let before = sim.fish
                sim.step(delta: frame, configuration: config)
                for (f, previous) in zip(sim.fish, before) {
                    totalFrames += 1
                    // Yaw swept in one direction without pausing: a U-turn is π, a pinwheel is 2π or more.
                    // A near-stop (under 0.1 rad per movement unit) separates two turns.
                    let turn = AquariumSimulation.angleDifference(f.yaw, previous.yaw)
                    let running = sweep[f.id] ?? 0
                    sweep[f.id] = abs(turn) < 0.1 * movement ? 0 : (running * turn > 0 ? running + turn : turn)
                    longestSweep = max(longestSweep, abs(sweep[f.id]!))
                    if abs(cos(f.yaw)) < 0.3 {
                        headOnFrames += 1
                        // Real travel: across the screen, or nearer/farther from the viewer.
                        // Feeding fish deliberately pivot toward food, so only wandering turns count.
                        let travel = hypot(f.x - previous.x, (f.depth - previous.depth) / AquariumSimulation.depthTravel)
                        if f.feeding == nil { wanderingHeadOnFrames += 1 }
                        if f.feeding == nil && travel > f.species.cruiseSpeed * 0.1 * movement { movingHeadOnFrames += 1 }
                        headOnRun[f.id, default: 0] += 1
                        longestHeadOn = max(longestHeadOn, headOnRun[f.id]!)
                    } else { headOnRun[f.id] = 0 }
                    if abs(f.depth - f.homeDepth) > 0.03 { leftHome.insert(f.id) }
                    if f.facingRight != previous.facingRight {
                        let quick = lastFlip[f.id].map { step - $0 < 60 } ?? false
                        if f.feeding == nil { flips += 1; if quick { quickFlipBacks += 1 } }
                        else { feedingFlips += 1; if quick { quickFeedingFlipBacks += 1 } }
                        lastFlip[f.id] = step
                    }
                    if f.feeding == nil {
                        let climb = max(f.forwardSpeed * 0.6, f.species.cruiseSpeed * 0.15)
                        t.check(abs(f.vy) <= climb + 0.000001, "Fish climb along a slope instead of rising vertically")
                    }
                }
            }
            t.check(headOnFrames > 100 && flips > 100, "Fish must actually turn")
            t.check(Double(movingHeadOnFrames) / Double(wanderingHeadOnFrames) > 0.8, "Most of a wandering turn keeps travelling instead of spinning in place (\(movingHeadOnFrames)/\(wanderingHeadOnFrames))")
            t.check(Double(headOnFrames) / Double(totalFrames) < 0.08, "Fish spend little time in the narrow head-on view")
            t.check(longestHeadOn < 5 * 30, "No fish lingers head-on for more than five seconds (\(longestHeadOn) frames)")
            t.check(Double(quickFlipBacks) / Double(flips) < 0.03, "A wandering turn is finished, not reversed within two seconds (\(quickFlipBacks)/\(flips))")
            // Food can move or be eaten by another fish, so a feeding fish may sensibly turn back sooner.
            t.check(Double(quickFeedingFlipBacks) / Double(max(1, feedingFlips)) < 0.15, "Feeding fish rarely dither between sides (\(quickFeedingFlipBacks)/\(feedingFlips))")
            t.check(leftHome.count > sim.fish.count / 2, "Turns carry fish nearer to or farther from the viewer")
            t.check(longestSweep < 5.0, "No fish spins round a full circle (longest one-way sweep \(String(format: "%.2f", longestSweep)) rad)")
        }
    }

    // MARK: Individual chance

    @MainActor static func individualityTests(_ t: TestRun) {
        t.test("decisions come at random moments and paths meander between them") {
            var wanderer = FishNavigation(seed: 4242, heading: 0)
            let openWater = SwimRegion(left: -100, right: 100, bottom: -100, top: 100)
            var intervals: [Double] = [], sinceDecision = 0.0, curvingFrames = 0, frames = 0
            for _ in 0..<60_000 {
                let decisions = wanderer.decisions, heading = wanderer.heading
                wanderer.advance(delta: frame, x: 0, y: 0, region: openWater, resting: false)
                sinceDecision += frame
                if wanderer.decisions != decisions { intervals.append(sinceDecision); sinceDecision = 0 }
                else { frames += 1; if abs(AquariumSimulation.angleDifference(wanderer.heading, heading)) > 0.0005 { curvingFrames += 1 } }
            }
            let mean = intervals.reduce(0, +) / Double(intervals.count)
            let deviation = sqrt(intervals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(intervals.count))
            // Evenly spread waits would vary by about 40% of their mean; random events vary by about 100%.
            t.check(deviation / mean > 0.7, "Waits between decisions are irregular like random events (variation \(String(format: "%.2f", deviation / mean)))")
            t.check(Double(curvingFrames) / Double(frames) > 0.8, "Between decisions the heading keeps meandering instead of running straight")
        }
        t.test("each fish keeps its own temperament") {
            let config = population([.rasbora: 24])
            var sim = AquariumSimulation(seed: 31); sim.synchronize(config)
            var firstHalf: [Int: Double] = [:], secondHalf: [Int: Double] = [:]
            for step in 0..<36_000 {
                sim.step(delta: frame, configuration: config)
                for f in sim.fish {
                    if step < 18_000 { firstHalf[f.id, default: 0] += f.forwardSpeed } else { secondHalf[f.id, default: 0] += f.forwardSpeed }
                }
            }
            let ids = sim.fish.map(\.id)
            let a = ids.map { firstHalf[$0]! }, b = ids.map { secondHalf[$0]! }
            t.check(a.max()! / a.min()! > 1.2, "Individuals of one species swim at noticeably different speeds")
            let meanA = a.reduce(0, +) / Double(a.count), meanB = b.reduce(0, +) / Double(b.count)
            let covariance = zip(a, b).map { ($0 - meanA) * ($1 - meanB) }.reduce(0, +)
            let correlation = covariance / sqrt(a.map { ($0 - meanA) * ($0 - meanA) }.reduce(0, +) * b.map { ($0 - meanB) * ($0 - meanB) }.reduce(0, +))
            t.check(correlation > 0.4, "A fish that is quick in one half hour is quick in the next (correlation \(String(format: "%.2f", correlation)))")
            t.check(Set(sim.fish.map(\.personality.boldness)).count == sim.fish.count, "Every fish rolls its own temperament")
        }
    }

    // MARK: Bottom dwellers

    @MainActor static func bottomDwellerTests(_ t: TestRun) {
        t.test("shrimp shelter cycles, varied crab directions, and complete refuge freeze") {
            var config = population([.shrimp: 6, .crab: 6])
            config.swimmingSpeed = 1
            for theme in AquariumTheme.allCases {
                config.theme = theme
                var sim = AquariumSimulation(seed: 1928); sim.synchronize(config)
                var phases = Set<ShrimpPhase>(), hiding = Set<Int>(), directions: [Int: Set<Int>] = [:]
                var maximumHeight = 0.0
                for _ in 0..<18000 {
                    sim.step(delta: frame, configuration: config)
                    for resident in sim.fish {
                        if resident.species == .shrimp {
                            let behavior = resident.shrimpBehavior
                            phases.insert(behavior.phase); maximumHeight = max(maximumHeight, resident.y)
                            if behavior.concealment > 0.9 {
                                hiding.insert(resident.id)
                                t.check(hypot(resident.x - behavior.target.x, (resident.y - behavior.target.y) * 0.65) < 0.026, "Shrimp must reach a refuge before hiding")
                            }
                        }
                        if abs(resident.vx) > 0.0005 { directions[resident.id, default: []].insert(resident.vx < 0 ? 0 : 1) }
                        if abs(resident.vy) > 0.0005 { directions[resident.id, default: []].insert(resident.vy < 0 ? 2 : 3) }
                    }
                }
                t.check(phases == Set(ShrimpPhase.allCases) && hiding.count >= 3, "Shrimp must graze, drift, seek cover, hide and emerge independently in \(theme)")
                t.check(maximumHeight > AquariumSimulation.region(for: .loach, theme: theme).top + 0.03, "Shrimp should occasionally drift above the substrate")
                t.check(directions.values.filter { $0.count == 4 }.count >= 10, "Crabs and shrimp must explore left, right, forward and back")
                let snapshot = sim.fish.map { [$0.x, $0.y, $0.yaw, $0.finPhase, $0.shrimpBehavior.concealment, $0.shrimpBehavior.remaining] }
                var paused = config; paused.mode = .still
                run(&sim, frames: 60, paused)
                t.check(snapshot == sim.fish.map { [$0.x, $0.y, $0.yaw, $0.finPhase, $0.shrimpBehavior.concealment, $0.shrimpBehavior.remaining] }, "Still must freeze shelter timers, crawling and concealment")
            }
        }
    }

    // MARK: Crab and shrimp gaits

    @MainActor static func crabAndShrimpGaitTests(_ t: TestRun) {
        t.test("crabs walk sideways in stop-and-go bursts") {
            var config = population([.crab: 8])
            config.theme = .river
            var sim = AquariumSimulation(seed: 606); sim.synchronize(config)
            var sideways = 0.0, forward = 0.0, walkingFrames = 0, frames = 0, legsWhileStill = 0.0
            var runs: [Int: Int] = [:], bouts: [Int] = [], allBursts = 0, sidewaysBursts = 0
            var burstStart: [Int: (x: Double, y: Double)] = [:], burstLengths: [Double] = []
            for _ in 0..<18_000 {
                let before = sim.fish
                sim.step(delta: frame, configuration: config)
                for (f, previous) in zip(sim.fish, before) {
                    frames += 1
                    if f.crabGait.walking && !previous.crabGait.walking { burstStart[f.id] = (f.x, f.y) }
                    if !f.crabGait.walking && previous.crabGait.walking, let start = burstStart[f.id] {
                        burstLengths.append(hypot(f.x - start.x, f.y - start.y) / f.species.bodyLength)
                    }
                    if f.crabGait.bouts != previous.crabGait.bouts {
                        allBursts += 1
                        if abs(cos(f.crabGait.direction)) > 0.7 { sidewaysBursts += 1 }
                    }
                    sideways += abs(f.x - previous.x); forward += abs(f.y - previous.y)
                    let moving = hypot(f.x - previous.x, f.y - previous.y) > f.species.cruiseSpeed * 0.2 * frame * config.swimmingSpeed
                    if moving { walkingFrames += 1; runs[f.id, default: 0] += 1 }
                    else {
                        legsWhileStill += abs(f.finPhase - previous.finPhase)
                        if let run = runs[f.id], run > 0 { bouts.append(run) }
                        runs[f.id] = 0
                    }
                }
            }
            burstLengths.sort()
            t.check(burstLengths[burstLengths.count / 2] > 0.35, "A scuttle covers a visible distance (median \(String(format: "%.2f", burstLengths[burstLengths.count / 2])) body lengths)")
            t.check(Double(sidewaysBursts) / Double(max(1, allBursts)) > 0.75, "Most bursts head sideways (\(sidewaysBursts)/\(allBursts))")
            t.check(sideways > forward * 2.5, "Crabs travel mostly sideways (\(String(format: "%.3f", sideways)) vs \(String(format: "%.3f", forward)))")
            let walking = Double(walkingFrames) / Double(frames)
            t.check(walking > 0.2 && walking < 0.7, "Crabs pause often between bursts (walking \(Int(walking * 100))% of the time)")
            let mean = Double(bouts.reduce(0, +)) / Double(bouts.count)
            let deviation = sqrt(bouts.map { (Double($0) - mean) * (Double($0) - mean) }.reduce(0, +) / Double(bouts.count))
            t.check(bouts.count > 100 && deviation / mean > 0.5, "Bursts vary in length (\(bouts.count) bursts)")
            t.check(legsWhileStill / Double(frames - walkingFrames) < 0.02, "Legs rest while a crab stands still")
        }
        t.test("animals on the bed lie side by side instead of piling up") {
            var config = population([.loach: 6, .crab: 6, .shrimp: 6])
            config.theme = .grove
            var sim = AquariumSimulation(seed: 23); sim.synchronize(config)
            run(&sim, frames: 900, config)
            var pairFrames: [String: Int] = [:], piled: [String: Int] = [:]
            for step in 0..<18_000 {
                if step % 1800 == 0 { sim.feed(config) }
                sim.step(delta: frame, configuration: config)
                let bed = sim.fish.filter { !$0.shrimpBehavior.isEscaping }
                for i in bed.indices { for j in bed.indices where j > i {
                    let a = bed[i], b = bed[j]
                    guard abs(a.depth - b.depth) < AquariumSimulation.bedLayer else { continue }
                    let kind = [a.species.rawValue, b.species.rawValue].sorted().joined(separator: "-") + (a.feeding != nil || b.feeding != nil ? " feeding" : "")
                    pairFrames[kind, default: 0] += 1
                    let meanLength = (a.species.bodyLength * a.depth + b.species.bodyLength * b.depth) / 2
                    if abs(a.x - b.x) < meanLength * 0.5 && abs(a.y - b.y) < 0.01 { piled[kind, default: 0] += 1 }
                } }
            }
            // Wandering residents keep their distance; crowding round food is allowed a little more.
            for kind in ["loach-loach", "crab-loach", "crab-crab", "shrimp-shrimp"] {
                for (suffix, limit) in [("", 0.015), (" feeding", 0.05)] {
                    let share = Double(piled[kind + suffix] ?? 0) / Double(max(1, pairFrames[kind + suffix] ?? 0))
                    t.check(share < limit, "\(kind)\(suffix) pairs at the same depth rarely lie on top of each other (\(String(format: "%.2f", share * 100))%)")
                }
            }
        }
        t.test("a crab never seems to stand on a loach, even at the food") {
            var config = population([.loach: 6, .crab: 6])
            for theme in AquariumTheme.allCases {
                config.theme = theme
                var sim = AquariumSimulation(seed: 71); sim.synchronize(config)
                var pairs = 0, onTop = 0
                for step in 0..<9_000 {
                    if step % 900 == 0 { sim.feed(config) }
                    sim.step(delta: frame, configuration: config)
                    let crabs = sim.fish.filter { $0.species == .crab }, loaches = sim.fish.filter { $0.species == .loach }
                    for crab in crabs { for loach in loaches {
                        pairs += 1
                        // On screen, including the bed's perspective lift.
                        let dy = (crab.y + AquariumSimulation.bedLift(crab.depth)) - (loach.y + AquariumSimulation.bedLift(loach.depth))
                        if abs(crab.x - loach.x) < loach.species.bodyLength * loach.depth * 0.4 && abs(dy) < 0.012 { onTop += 1 }
                    } }
                }
                let share = Double(onTop) / Double(pairs)
                t.check(share < 0.01, "Crabs rarely sit centred on a loach in \(theme) (\(String(format: "%.2f", share * 100))%)")
            }
        }
        t.test("shrimp pick their way in steps and dart away from fish that hunt them") {
            var config = population([.shrimp: 10, .cherry: 8, .koi: 3])
            config.theme = .river
            var sim = AquariumSimulation(seed: 717); sim.synchronize(config)
            var grazingStill = 0, grazingStepping = 0, fleeingFrames = 0, awayFrames = 0, fleeingFrom: [Int: Int] = [:]
            var dartStart: [Int: (x: Double, y: Double)] = [:], darts: [Double] = []
            for step in 0..<27_000 {
                if step % 900 == 0 { sim.feed(config) }
                let before = sim.fish
                sim.step(delta: frame, configuration: config)
                let hunters = sim.fish.filter(\.species.huntsShrimp)
                for (f, previous) in zip(sim.fish, before) where f.species == .shrimp {
                    let behavior = f.shrimpBehavior
                    if behavior.phase == .grazing && f.feeding == nil && !behavior.isEscaping {
                        if behavior.stepping { grazingStepping += 1 } else { grazingStill += 1 }
                    }
                    if behavior.holdsPosition { t.check(!behavior.isEscaping, "A hidden shrimp stays put") }
                    // Follow each escape a hunter set off; the gap to that hunter must open.
                    if behavior.escapes != previous.shrimpBehavior.escapes {
                        let nearest = hunters.min { hypot($0.x - f.x, $0.y - f.y) < hypot($1.x - f.x, $1.y - f.y) }
                        fleeingFrom[f.id] = nearest.flatMap {
                            hypot($0.x - f.x, ($0.y - f.y) * AquariumSimulation.verticalWeight) < AquariumSimulation.threatDistance ? $0.id : nil
                        }
                    }
                    if behavior.escapes != previous.shrimpBehavior.escapes { dartStart[f.id] = (f.x, f.y) }
                    if !behavior.isEscaping && previous.shrimpBehavior.isEscaping, let start = dartStart[f.id] {
                        darts.append(hypot(f.x - start.x, f.y - start.y) / f.species.bodyLength)
                    }
                    guard behavior.isEscaping, let hunterID = fleeingFrom[f.id], let hunter = hunters.first(where: { $0.id == hunterID }),
                          abs(f.x - previous.x) > 1e-9 else { continue }
                    fleeingFrames += 1
                    if (f.x - previous.x) * (f.x - hunter.x) > 0 { awayFrames += 1 }
                }
            }
            t.check(grazingStill > grazingStepping && grazingStepping > 500, "Grazing shrimp mostly stand and pick, with short steps between")
            t.check(fleeingFrames > 30, "Hunting fish diving for food make shrimp flee (\(fleeingFrames) fleeing frames)")
            t.check(Double(awayFrames) / Double(max(1, fleeingFrames)) > 0.9, "Shrimp dart away from the hunter, not toward it (\(awayFrames)/\(fleeingFrames))")
            var gentle = population([.shrimp: 10, .loach: 6, .danio: 10])
            gentle.theme = .river
            var calm = AquariumSimulation(seed: 717); calm.synchronize(gentle)
            run(&calm, frames: 18_000, gentle)
            let calmEscapes = calm.fish.filter { $0.species == .shrimp }.map(\.shrimpBehavior.escapes).reduce(0, +)
            // Only the rare spontaneous flick: about one per shrimp every few minutes.
            t.check(calmEscapes < 10 * 4, "Loaches and danios do not frighten shrimp (\(calmEscapes) escapes)")
            darts.sort()
            t.check(darts.count > 10 && darts[darts.count / 10] > 1.0, "Even short darts cover more than a body length, never stopped dead at the edge (10th percentile \(String(format: "%.2f", darts.isEmpty ? 0 : darts[darts.count / 10])))")
        }
    }

    // MARK: Navigation

    @MainActor static func navigationTests(_ t: TestRun) {
        t.test("independent random navigation with partial turns and reversals") {
            var wanderer = FishNavigation(seed: 231, heading: 0), twin = FishNavigation(seed: 231, heading: 0)
            var other = FishNavigation(seed: 902, heading: 0)
            let openWater = SwimRegion(left: 0, right: 1, bottom: 0, top: 1)
            var shortTurns = 0, wideTurns = 0, reversals = 0, leftTurns = 0, rightTurns = 0
            var paces: [Double] = [], turnRates: [Double] = [], intervals: [Double] = []
            for _ in 0..<36000 {
                let before = wanderer.decisions
                wanderer.advance(delta: frame, x: 0.5, y: 0.5, region: openWater, resting: false)
                // Consuming another individual's stream must not change this fish's choices.
                for _ in 0..<3 { other.advance(delta: frame, x: 0.5, y: 0.5, region: openWater, resting: false) }
                twin.advance(delta: frame, x: 0.5, y: 0.5, region: openWater, resting: false)
                t.check(wanderer.heading == twin.heading && wanderer.remaining == twin.remaining, "Fish navigation random streams must be independent")
                guard wanderer.decisions != before else { continue }
                let angle = abs(wanderer.lastTurn)
                t.check(angle <= .pi, "An intention chooses a partial turn or reversal, never a full circle")
                if angle < .pi / 4 { shortTurns += 1 } else if angle < 2.4 { wideTurns += 1 } else { reversals += 1 }
                if wanderer.lastTurn < 0 { leftTurns += 1 } else { rightTurns += 1 }
                paces.append(wanderer.speedFactor); turnRates.append(wanderer.turnLimit); intervals.append(wanderer.remaining)
            }
            t.check(shortTurns > wideTurns && wideTurns > reversals && reversals > 15, "Navigation must mix small changes, wider turns, and occasional reversals")
            t.check(leftTurns > 100 && rightTurns > 100, "Fish must turn in both directions")
            t.check(paces.max()! / paces.min()! > 2 && turnRates.max()! / turnRates.min()! > 2 && intervals.max()! / intervals.min()! > 3, "Fish need varied swimming speed, turning speed, and decision timing")
            let restingHeading = wanderer.heading
            for _ in 0..<300 { wanderer.advance(delta: frame, x: 0.5, y: 0.5, region: openWater, resting: true) }
            t.check(wanderer.heading == restingHeading, "Resting must hold an intention instead of repeatedly choosing turns")
        }
        t.test("adding residents elsewhere never changes another fish's chances") {
            let fishOnly = population([.rasbora: 6, .golden: 4])
            var withCrabs = fishOnly; withCrabs.setCount(.crab, 5)
            var a = AquariumSimulation(seed: 55), b = AquariumSimulation(seed: 55)
            a.synchronize(fishOnly); b.synchronize(withCrabs)
            run(&a, frames: 3600, fishOnly); run(&b, frames: 3600, withCrabs)
            let swimmers = b.fish.filter { $0.species != .crab }
            t.check(a.fish.map { [$0.x, $0.y, $0.yaw] } == swimmers.map { [$0.x, $0.y, $0.yaw] }, "Crabs on the sand leave the swimmers' paths untouched")
        }
        t.test("Still freezes navigation; bubbles never change fish choices") {
            let natural = AquariumConfiguration()
            var sim = AquariumSimulation(seed: 12345); sim.synchronize(natural)
            run(&sim, frames: 600, natural)
            let snapshot = sim.fish.map { [$0.navigation.heading, $0.navigation.remaining, Double($0.navigation.decisions), $0.pitch, $0.depth] }
            var still = natural; still.mode = .still
            run(&sim, frames: 120, still)
            t.check(sim.fish.map { [$0.navigation.heading, $0.navigation.remaining, Double($0.navigation.decisions), $0.pitch, $0.depth] } == snapshot, "Still freezes navigation decisions, pitch, and depth")
            var bubbleTwin = AquariumSimulation(seed: 908), plainTwin = AquariumSimulation(seed: 908)
            var withBubbles = natural; withBubbles.bubbles = true
            bubbleTwin.synchronize(withBubbles); plainTwin.synchronize(natural)
            for _ in 0..<1800 { bubbleTwin.step(delta: frame, configuration: withBubbles); plainTwin.step(delta: frame, configuration: natural) }
            t.check(bubbleTwin.fish.map { [$0.x, $0.y, $0.yaw] } == plainTwin.fish.map { [$0.x, $0.y, $0.yaw] }, "Bubble randomness must not affect fish choices")
            t.check(!bubbleTwin.bubbles.isEmpty, "Bubbles were actually rising alongside the fish")
        }
    }

    // MARK: Strokes

    @MainActor static func strokeTests(_ t: TestRun) {
        t.test("non-looping stroke variation, glides, and stronger dashes") {
            // Hold speed constant to detect a short mechanical loop independent of mood changes.
            for species in FishSpecies.allCases {
                var stroke = FishStroke(seed: 91), twin = FishStroke(seed: 91), neighbor = FishStroke(seed: 193)
                var rates: [Double] = [], powers: [Double] = [], independentFrames = 0
                for step in 0..<3600 {
                    let before = stroke
                    stroke.advance(delta: 1.0 / 60, species: species, speed: 0.85, acceleration: 0, turnRate: 0)
                    twin.advance(delta: 1.0 / 60, species: species, speed: 0.85, acceleration: 0, turnRate: 0)
                    neighbor.advance(delta: 1.0 / 60, species: species, speed: 0.85, acceleration: 0, turnRate: 0)
                    t.check(stroke.amplitude == twin.amplitude && stroke.pectoralPhase == twin.pectoralPhase, "Motion must remain reproducible for a fixed seed")
                    t.check(abs(stroke.amplitude - before.amplitude) < 0.055 && abs(stroke.tailRate - before.tailRate) < 0.45, "Random stroke changes must ease without a twitch")
                    t.check(stroke.pectoralPhase > before.pectoralPhase && stroke.dorsalPhase > before.dorsalPhase, "Balancing fins must advance independently")
                    if abs(stroke.amplitude - neighbor.amplitude) > 0.025 { independentFrames += 1 }
                    if step > 120 { rates.append(stroke.tailRate); powers.append(stroke.amplitude) }
                }
                t.check(rates.max()! / rates.min()! > 1.25 && powers.max()! / powers.min()! > 1.6, "Steady swimming must vary cadence and include softer glides for \(species)")
                t.check(independentFrames > 1800, "Neighboring fish must not share one stroke loop")
                var hover = FishStroke(seed: 9), dash = FishStroke(seed: 9)
                for _ in 0..<300 {
                    hover.advance(delta: 1.0 / 60, species: species, speed: 0.03, acceleration: 0, turnRate: 0)
                    dash.advance(delta: 1.0 / 60, species: species, speed: 2.5, acceleration: 0.5, turnRate: 0.7)
                }
                t.check(dash.amplitude > hover.amplitude * 4 && dash.tailRate > hover.tailRate * 2, "Dashing recruits stronger and faster tail strokes")
                t.check(hover.finAmplitude > 0.3 && hover.amplitude < 0.10, "Hovering keeps balancing fins alive while the tail rests")
            }
        }
        t.test("zero speed and Still freeze all motor rhythms") {
            let natural = AquariumConfiguration()
            var sim = AquariumSimulation(seed: 12345); sim.synchronize(natural)
            run(&sim, frames: 300, natural)
            let snapshot = sim.fish.map { [$0.stroke.pectoralPhase, $0.stroke.dorsalPhase, $0.stroke.amplitude, $0.stroke.bend] }
            var stopped = natural; stopped.swimmingSpeed = 0
            run(&sim, frames: 120, stopped)
            t.check(sim.fish.map { [$0.stroke.pectoralPhase, $0.stroke.dorsalPhase, $0.stroke.amplitude, $0.stroke.bend] } == snapshot, "Zero speed freezes all motor rhythms")
            stopped = natural; stopped.mode = .still
            run(&sim, frames: 120, stopped)
            t.check(sim.fish.map { [$0.stroke.pectoralPhase, $0.stroke.dorsalPhase, $0.stroke.amplitude, $0.stroke.bend] } == snapshot, "Still freezes all motor rhythms")
        }
    }

    // MARK: Feeding

    @MainActor static func feedingTests(_ t: TestRun) {
        t.test("feeding portions are bounded, eaten, and frozen by Still") {
            let natural = AquariumConfiguration()
            var sim = AquariumSimulation(seed: 12345); sim.synchronize(natural)
            run(&sim, frames: 300, natural)
            sim.feed(natural)
            t.check(sim.food.count + sim.pendingFood.count == 12, "Feeding drops a small portion")
            var still = natural; still.mode = .still
            let pausedFood = sim.food.map { [$0.x, $0.y, $0.age] }
            let pausedFish = sim.fish.map { [$0.x, $0.y, $0.yaw, $0.finPhase, $0.activity] }
            sim.feed(still)
            run(&sim, frames: 60, still)
            t.check(sim.food.map { [$0.x, $0.y, $0.age] } == pausedFood && sim.fish.map { [$0.x, $0.y, $0.yaw, $0.finPhase, $0.activity] } == pausedFish, "Still mode freezes food, turns, and fins and ignores feed requests")
            run(&sim, frames: 4800, natural)
            t.check(sim.mealsEaten > 0, "Fish must actually reach and eat food")
            t.check(sim.food.isEmpty, "Food must be eaten or expire")
            for _ in 0..<20 { sim.feed(natural) }
            t.check(sim.food.count + sim.pendingFood.count == 36, "Repeated feeding must stay bounded")
            var changed = natural; changed.theme = .spring
            sim.synchronize(changed)
            t.check(sim.food.isEmpty && sim.pendingFood.isEmpty, "Scene changes must clear old food")
        }
        t.test("every species reacts promptly, eats, and disperses in every scene") {
            for theme in AquariumTheme.allCases {
                for species in FishSpecies.allCases {
                    var config = population([species: 8]); config.theme = theme
                    var sim = AquariumSimulation(seed: 12345); sim.synchronize(config)
                    run(&sim, frames: 600, config)
                    sim.feed(config)
                    var firstApproach: Double?, phases = Set<FeedingPhase>(), reactionTimes: [Int: Int] = [:], leftUsualBand = false
                    var approachFrames = 0, recedingFrames = 0, travelFrames = 0, liftFrames = 0
                    for step in 0..<5400 {
                        let before = sim.fish
                        sim.step(delta: frame, configuration: config)
                        for (f, previous) in zip(sim.fish, before) {
                            let dx = abs(f.x - previous.x), dy = abs(f.y - previous.y)
                            // Only real travel counts; a slow settle of a few percent of cruise speed is not a lift.
                            if f.feeding != nil && !species.isBottomDweller && hypot(dx, dy) > species.cruiseSpeed * 0.3 * frame * config.swimmingSpeed {
                                travelFrames += 1
                                if dy > dx * 3 { liftFrames += 1 }
                            }
                            if let response = f.feeding, response.phase == .approaching, previous.feeding?.phase == .approaching,
                               response.targetID == previous.feeding?.targetID {
                                approachFrames += 1
                                // Measured against last frame's pellet position, so only the fish's own motion counts.
                                let target = previous.feeding!
                                let now = hypot(target.x - f.x, (target.y - f.y) * 0.55)
                                let then = hypot(target.x - previous.x, (target.y - previous.y) * 0.55)
                                if now > then + 0.00002 { recedingFrames += 1 }
                            }
                            if let phase = f.feeding?.phase {
                                phases.insert(phase)
                                if phase == .approaching && reactionTimes[f.id] == nil {
                                    reactionTimes[f.id] = step
                                    if firstApproach == nil { firstApproach = Double(step) * frame }
                                }
                            }
                            if f.y > AquariumSimulation.region(for: species, theme: theme).top { leftUsualBand = true }
                            t.check(f.x.isFinite && f.y.isFinite && f.y >= 0 && f.y <= 1, "Feeding stays in valid water coordinates")
                        }
                    }
                    t.check(Double(liftFrames) / Double(max(1, travelFrames)) < 0.25, "\(species) swims along a slope to and from food, not straight up and down like a lift, in \(theme) (\(liftFrames)/\(travelFrames))")
                    // Several bottom feeders crowding one pellet on a shallow bed jostle a little more.
                    let recedingLimit = species.isBottomDweller ? 0.10 : 0.08
                    t.check(Double(recedingFrames) / Double(max(1, approachFrames)) < recedingLimit, "\(species) must close in on its pellet while approaching in \(theme) (\(recedingFrames)/\(approachFrames))")
                    t.check((firstApproach ?? 100) < 1.5, "\(species) must visibly respond within 1.5 seconds in \(theme)")
                    t.check(phases.isSuperset(of: [.noticing, .approaching, .nibbling, .leaving]), "Feeding must include notice, approach, eating, and departure")
                    t.check(Set(reactionTimes.values).count > 1, "Fish must react at different times")
                    t.check(sim.mealsEaten > 0 && sim.food.isEmpty, "\(species) must be able to eat and food must clear in \(theme)")
                    t.check(sim.fish.allSatisfy { $0.feeding == nil }, "\(species) must finish feeding and resume its own behavior in \(theme)")
                    if species == .cherry { t.check(leftUsualBand, "Food above the normal swimming band must remain reachable") }
                }
            }
        }
        t.test("after a meal, fish settle back and are ready to feed again") {
            var config = population(Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map { ($0, 6) }))
            config.theme = .river
            for seed in [1, 7, 99] as [UInt64] {
                var sim = AquariumSimulation(seed: seed); sim.synchronize(config)
                var leavingSince: [Int: Int] = [:], longest = 0
                for step in 0..<18_000 {
                    if step % 450 == 0 { sim.feed(config) }
                    sim.step(delta: frame, configuration: config)
                    for f in sim.fish {
                        if f.feeding?.phase == .leaving { leavingSince[f.id, default: step] = leavingSince[f.id] ?? step; longest = max(longest, step - leavingSince[f.id]!) }
                        else { leavingSince[f.id] = nil }
                    }
                }
                t.check(Double(longest) * frame < 15, "No fish spends more than 15 s leaving food (seed \(seed): \(Double(longest) * frame) s)")
            }
        }
        t.test("feeding timers freeze with Still and zero speed") {
            let natural = AquariumConfiguration()
            var sim = AquariumSimulation(); sim.synchronize(natural); sim.feed(natural)
            run(&sim, frames: 60, natural)
            let reactions = sim.fish.map { $0.feeding?.age }
            var frozen = natural; frozen.mode = .still
            run(&sim, frames: 120, frozen)
            t.check(sim.fish.map { $0.feeding?.age } == reactions, "Still mode freezes feeding response timers too")
            frozen.mode = .live; frozen.swimmingSpeed = 0
            run(&sim, frames: 120, frozen)
            t.check(sim.fish.map { $0.feeding?.age } == reactions, "Zero swimming speed freezes feeding response timers")
        }
        t.test("a full tank feeding at maximum population stays fast") {
            var config = population(Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map { ($0, 12) }))
            config.swimmingSpeed = 1
            var sim = AquariumSimulation(seed: 5); sim.synchronize(config)
            for _ in 0..<3 { sim.feed(config) }
            let start = Date()
            run(&sim, frames: 1800, config)
            let perFrame = Date().timeIntervalSince(start) / 1800
            t.check(perFrame < 0.002, "A 120-fish feeding frame must simulate in under 2 ms (took \(String(format: "%.3f", perFrame * 1000)) ms)")
            t.check(sim.mealsEaten > 0, "A crowded tank must still eat")
        }
    }

    // MARK: Atmosphere

    @MainActor static func atmosphereTests(_ t: TestRun) {
        t.test("bubbles rise in streams at real sizes, speeds, and depths") {
            var config = AquariumConfiguration(); config.bubbles = true; config.swimmingSpeed = 0
            var sim = AquariumSimulation(); sim.synchronize(config)
            let dt = 1.0 / 60
            var seen: [Int: BubbleState] = [:], counts: [Int] = []
            for step in 0..<3600 {
                let previous = Dictionary(uniqueKeysWithValues: sim.bubbles.map { ($0.id, $0) })
                sim.step(delta: dt, configuration: config)
                if step > 600 { counts.append(sim.bubbles.count) }
                for bubble in sim.bubbles {
                    seen[bubble.id] = bubble
                    t.check((sim.visibleRegion.left...sim.visibleRegion.right).contains(bubble.x), "Bubbles stay in the visible water")
                    guard let before = previous[bubble.id] else { continue }
                    t.check(bubble.y > before.y, "Bubbles rise steadily")
                    t.check(bubble.y - before.y <= bubble.riseSpeed * dt + 1e-9, "Bubbles never jump past their terminal speed")
                    let lateralLimit = bubble.zigzagAmplitude * 2 * .pi * bubble.zigzagFrequency * dt + 1e-9
                    t.check(abs(bubble.x - before.x) <= lateralLimit, "Side-to-side motion is a smooth zigzag, never a jump")
                }
            }
            let all = Array(seen.values)
            let diameters = all.map(\.diameter).sorted()
            t.check(diameters.first! < 0.9 && diameters.last! > 3, "Streams mix tiny plant bubbles with air-stone bubbles of a few millimetres (\(diameters.first!)–\(diameters.last!) mm)")
            let median = diameters[diameters.count / 2]
            t.check(median > 1.2 && median < 3, "Most bubbles are about two millimetres (median \(median))")
            for bubble in all {
                let speed = bubble.riseSpeed * TankScale.waterHeightCM
                t.check(speed > 3 && speed < 25, "Bubbles rise at measured speeds, 3 to 25 cm/s (\(speed))")
                if bubble.diameter < 0.7 { t.check(bubble.aspect < 1.01 && bubble.zigzagAmplitude == 0, "Tiny bubbles stay round and rise straight") }
                if bubble.diameter > 2.5 { t.check(bubble.aspect > 1.2 && bubble.zigzagAmplitude > 0, "Larger bubbles flatten and zigzag") }
            }
            let small = all.filter { $0.diameter < 1 }.map(\.riseSpeed), large = all.filter { $0.diameter > 2.5 }.map(\.riseSpeed)
            t.check(small.max()! < large.min()!, "Larger bubbles rise faster")
            let depths = all.map(\.depth)
            t.check(depths.max()! - depths.min()! > 0.15, "Streams rise at clearly different distances from the viewer")
            t.check(counts.min()! > 3 && counts.max()! <= BubbleField.maximumBubbles, "A steady, bounded number of bubbles is in the water (\(counts.min()!)–\(counts.max()!))")
            let snapshot = sim.bubbles.map { [$0.x, $0.y, $0.age] }
            config.mode = .still
            run(&sim, frames: 120, config)
            t.check(sim.bubbles.map { [$0.x, $0.y, $0.age] } == snapshot, "Still mode freezes bubbles")
            var cropped = AquariumSimulation(); cropped.visibleRegion = SwimRegion(left: 0.3, right: 0.7, bottom: 0.035, top: 0.9)
            cropped.synchronize(config)
            config.mode = .live
            run(&cropped, frames: 600, config)
            t.check(cropped.bubbles.allSatisfy { (0.3...0.7).contains($0.x) }, "On a narrow display the streams move into view")
        }
        t.test("residents stir the sand, and it settles again") {
            var config = population([.loach: 6, .crab: 6, .shrimp: 6, .rasbora: 8])
            config.theme = .river
            var sim = AquariumSimulation(seed: 41); sim.synchronize(config)
            var maximumGrains = 0, clouds = 0
            for step in 0..<18_000 {
                if step % 1800 == 0 { sim.feed(config) }
                sim.step(delta: frame, configuration: config)
                maximumGrains = max(maximumGrains, sim.sand.grains.count)
                for grain in sim.sand.grains {
                    t.check(grain.y >= grain.floor - 1e-9, "Sand never sinks below the bed")
                    if grain.isCloud { clouds += 1 }
                    if !grain.isCloud && grain.age > 1.2 { t.check(abs(grain.y - grain.floor) < TankScale.height(cm: 1), "Thrown-up grains settle back to the bed") }
                }
            }
            t.check(sim.sand.puffs > 50, "Loaches, crabs, and shrimp kick up sand as they work the bed (\(sim.sand.puffs) puffs)")
            t.check(clouds > 0, "Stronger disturbances leave a faint silt cloud")
            t.check(maximumGrains <= SandField.maximumGrains, "Sand stays within its particle budget")
            let snapshot = sim.sand.grains.map { [$0.x, $0.y, $0.age] }
            config.mode = .still
            run(&sim, frames: 60, config)
            t.check(sim.sand.grains.map { [$0.x, $0.y, $0.age] } == snapshot, "Still mode freezes drifting sand")
            var swimmersOnly = population([.rasbora: 12])
            swimmersOnly.theme = .river
            var calm = AquariumSimulation(seed: 41); calm.synchronize(swimmersOnly)
            run(&calm, frames: 3600, swimmersOnly)
            t.check(calm.sand.puffs == 0, "Mid-water fish leave the sand undisturbed")
        }
        t.test("pellets arrive as varied, staggered 3D sprinkles") {
            let natural = AquariumConfiguration()
            var sim = AquariumSimulation(); sim.synchronize(natural); sim.feed(natural)
            t.check(sim.food.count == 1 && sim.pendingFood.count == 11, "Food must arrive as staggered sprinkles")
            let portion = sim.food + sim.pendingFood
            t.check(portion.contains { $0.depth < 0.7 } && portion.contains { $0.depth > 1.2 }, "Each feeding portion must span near and far water")
            t.check(ParticlePerspective.scale(1.3) > ParticlePerspective.scale(0.65) * 2, "Distance must visibly change particle size")
            t.check(Set(portion.map { Int($0.x * 100) }).count > 5, "Pellets must enter at different horizontal positions")
            t.check(Set(portion.map(\.sinkSpeed)).count > 5 && Set(portion.map(\.size)).count > 5, "Pellets need varied size and sinking speed")
            let orientations = portion.map { [Double($0.id), $0.tumble, $0.rotation, $0.depth] }
            let queue = sim.pendingFood.map(\.releaseDelay)
            var still = natural; still.mode = .still
            run(&sim, frames: 60, still)
            t.check(sim.pendingFood.map(\.releaseDelay) == queue, "Still mode freezes scheduled sprinkles")
            t.check((sim.food + sim.pendingFood).map { [Double($0.id), $0.tumble, $0.rotation, $0.depth] } == orientations, "Still mode freezes 3D pellet orientation and depth")
            run(&sim, frames: 45, natural)
            t.check(sim.pendingFood.isEmpty, "The portion finishes dropping within 1.5 seconds")
        }
    }

    // MARK: Wallpaper stills

    @MainActor static func wallpaperStillTests(_ t: TestRun) {
        t.test("wallpaper stills are pruned only when old, unused, and not among the newest") {
            let now = Date()
            let folder = URL(fileURLWithPath: "/stills", isDirectory: true)
            func still(_ name: String, daysOld: Double) -> WallpaperStills.Still {
                WallpaperStills.Still(url: folder.appendingPathComponent(name), created: now.addingTimeInterval(-daysOld * 86400))
            }
            // Twelve stills: the eight newest are kept regardless of age or use.
            var stills = (0..<12).map { still("s\($0).png", daysOld: Double($0) * 5) }
            stills.append(still("notes.txt", daysOld: 100))
            let inUse = [folder.appendingPathComponent("s10.png")]
            let removed = WallpaperStills.obsolete(existing: stills, keeping: inUse, now: now).map(\.lastPathComponent)
            t.check(removed == ["s8.png", "s9.png", "s11.png"], "Only old, unused PNGs beyond the newest eight are deleted (got \(removed))")
            let recent = (0..<12).map { still("r\($0).png", daysOld: Double($0) * 0.5) }
            t.check(WallpaperStills.obsolete(existing: recent, keeping: [], now: now).isEmpty, "Recent stills are kept, since another Space may show them")
            t.check(WallpaperStills.obsolete(existing: [], keeping: inUse, now: now).isEmpty, "An empty folder deletes nothing")
        }
    }
}
