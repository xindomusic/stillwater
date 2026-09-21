import Foundation
import CoreGraphics
import Combine

enum AquariumTheme: String, CaseIterable, Codable, Identifiable {
    case grove = "sunken-grove", river = "riverlight", spring = "willow-springs"
    var id: String { rawValue }
    var title: String {
        switch self { case .grove: return "Sunken Grove"; case .river: return "Riverlight"; case .spring: return "Willow Springs" }
    }
    var subtitle: String {
        switch self {
        case .grove: return "Sculptural wood and plants in crystal-clear water."
        case .river: return "Clear water, sunlit stones, and room to wander."
        case .spring: return "Clear spring water beneath sunlit willow roots."
        }
    }
    var tag: String {
        switch self { case .grove: return "PLANTED & PEACEFUL"; case .river: return "CLEAR & AIRY"; case .spring: return "FRESH & TRANQUIL" }
    }
    var assetName: String { switch self { case .grove: return "sunken-grove-crystal"; case .river: return "riverlight-crystal"; case .spring: return "willow-springs-crystal" } }
}

enum AquariumLighting: String, Codable, CaseIterable, Identifiable {
    case system, day, night
    var id: String { rawValue }
    var title: String { switch self { case .system: return "Follow Mac"; case .day: return "Day"; case .night: return "Night" } }
    func isNight(systemIsDark: Bool) -> Bool { self == .night || (self == .system && systemIsDark) }
}

enum AquariumMode: String, Codable, CaseIterable { case live, still }
enum RenderQuality: String, Codable, CaseIterable, Identifiable {
    case eco, balanced, smooth
    var id: String { rawValue }
    var fps: Int { switch self { case .eco: return 15; case .balanced: return 30; case .smooth: return 60 } }
    var title: String { switch self { case .eco: return "Quiet · 15 fps"; case .balanced: return "Balanced · 30 fps"; case .smooth: return "Fluid · 60 fps" } }
}

enum FishSpecies: String, CaseIterable, Codable, Identifiable {
    case rasbora, cherry, pearl, loach
    var id: String { rawValue }
    var name: String {
        switch self { case .rasbora: return "Harlequin rasbora"; case .cherry: return "Cherry barb"; case .pearl: return "Pearl gourami"; case .loach: return "Kuhli loach" }
    }
    var detail: String {
        switch self { case .rasbora: return "Copper & charcoal · gentle school"; case .cherry: return "Cherry red · curious explorer"; case .pearl: return "Pearlescent · unhurried glider"; case .loach: return "Gold & brown · sand forager" }
    }
    var defaultCount: Int { switch self { case .rasbora: return 12; case .cherry: return 8; case .pearl: return 2; case .loach: return 4 } }
    var bodySize: Double { switch self { case .rasbora: return 65; case .cherry: return 62; case .pearl: return 138; case .loach: return 112 } }
    var cruiseSpeed: Double { switch self { case .rasbora: return 0.033; case .cherry: return 0.028; case .pearl: return 0.017; case .loach: return 0.015 } }
    var legacyKey: String { switch self { case .rasbora: return "cardinal"; case .cherry: return "ember"; case .pearl: return "gourami"; case .loach: return "cory" } }

}

struct AquariumConfiguration: Codable, Equatable {
    var theme: AquariumTheme = .river
    var mode: AquariumMode = .live
    var swimmingSpeed: Double = 0.5
    var plantSway: Double = 0.55
    var shimmer: Double = 0.2
    var brightness: Double = 1.0
    // Optional storage lets older preferences decode without losing existing settings.
    var lighting: AquariumLighting? = nil
    var feedingShortcutEnabled: Bool? = nil
    var usesGlobalFeedingShortcut: Bool { feedingShortcutEnabled ?? true }
    var lightingMode: AquariumLighting { lighting ?? .system }
    var bubbles = false
    var particles = false
    var quality: RenderQuality = .balanced
    var allDisplays = true
    var wallpaperEnabled = true
    var counts: [String: Int] = Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map { ($0.rawValue, $0.defaultCount) })
    var totalFish: Int { FishSpecies.allCases.reduce(0) { $0 + count($1) } }
    func count(_ species: FishSpecies) -> Int { counts[species.rawValue] ?? counts[species.legacyKey] ?? species.defaultCount }
    mutating func setCount(_ species: FishSpecies, _ count: Int) { counts[species.rawValue] = min(30, max(0, count)) }
    mutating func sanitize() {
        swimmingSpeed = bounded(swimmingSpeed, 0...2, fallback: 0.5)
        plantSway = bounded(plantSway, 0...1, fallback: 0.55)
        shimmer = bounded(shimmer, 0...1, fallback: 0.2)
        brightness = bounded(brightness, 0.4...1.3, fallback: 1)
        counts = Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map { ($0.rawValue, min(30, max(0, count($0)))) })
    }
}

private func bounded(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
    value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
}

@MainActor final class AquariumStore: ObservableObject {
    @Published var configuration: AquariumConfiguration {
        didSet {
            if let data = try? JSONEncoder().encode(configuration) { defaults?.set(data, forKey: "aquarium.configuration.v1") }
        }
    }
    @Published var message: String? = nil
    @Published var feedingShortcutAvailable = false
    let feedRequests = PassthroughSubject<Void, Never>()
    private var lastFeed = -Double.infinity
    var canFeed: Bool { configuration.mode == .live && configuration.swimmingSpeed > 0 && configuration.totalFish > 0 }
    func requestFeed() {
        guard canFeed else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFeed > 3 else { return }
        lastFeed = now
        feedRequests.send()
        message = "Food is in the water. Watch your fish turn and gather."
    }
    private let defaults: UserDefaults?
    init(persist: Bool = true) {
        defaults = persist ? UserDefaults.standard : nil
        var initial = AquariumConfiguration()
        if let data = defaults?.data(forKey: "aquarium.configuration.v1"),
           let stored = try? JSONDecoder().decode(AquariumConfiguration.self, from: data) { initial = stored }
        initial.sanitize()
        configuration = initial
    }
    func restoreDefaults() { configuration = AquariumConfiguration() }
}

/// Deterministic randomness makes movement repeatable in verification, without a short animation loop.
struct AquariumRandom {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
    mutating func value(_ range: ClosedRange<Double>) -> Double { range.lowerBound + next() * (range.upperBound - range.lowerBound) }
}

struct SwimRegion {
    var left: Double, right: Double, bottom: Double, top: Double
    func constrain(x: Double, y: Double) -> (Double, Double) { (min(right, max(left, x)), min(top, max(bottom, y))) }
    func intersecting(_ visible: SwimRegion) -> SwimRegion {
        let x0 = max(left, visible.left), x1 = min(right, visible.right)
        let y0 = max(bottom, visible.bottom), y1 = min(top, visible.top)
        let fallbackX = min(visible.right, max(visible.left, (left + right) / 2))
        let fallbackY = min(visible.top, max(visible.bottom, (bottom + top) / 2))
        return SwimRegion(left: x0 <= x1 ? x0 : fallbackX, right: x0 <= x1 ? x1 : fallbackX,
                          bottom: y0 <= y1 ? y0 : fallbackY, top: y0 <= y1 ? y1 : fallbackY)
    }
}

/// Fish and artwork share this transform, including after cropping on a different display.
struct AquariumFraming {
    let imageRect: CGRect
    let visibleRegion: SwimRegion
    init(viewport: CGSize, image: CGSize) {
        let scale = max(viewport.width / max(1, image.width), viewport.height / max(1, image.height))
        let width = image.width * scale, height = image.height * scale
        // Anchor the sand to the bottom so a wide display never crops away the substrate.
        imageRect = CGRect(x: (viewport.width - width) / 2, y: 0, width: width, height: height)
        visibleRegion = SwimRegion(left: max(0, -imageRect.minX / max(1, width)) + 0.025,
                                   right: min(1, (viewport.width - imageRect.minX) / max(1, width)) - 0.025,
                                   bottom: 0.035, top: min(1, viewport.height / max(1, height)) - 0.04)
    }
    func point(x: Double, y: Double) -> CGPoint { CGPoint(x: imageRect.minX + x * imageRect.width, y: imageRect.minY + y * imageRect.height) }
}

enum FishMood: String, CaseIterable { case cruise, hover, dash, forage, feeding }

enum FeedingPhase: String { case noticing, approaching, nibbling, leaving }

struct FeedingResponse {
    var phase: FeedingPhase = .noticing
    var targetID: Int?
    var x: Double, y: Double
    var remaining: Double
    var age = 0.0
}

struct FishState: Identifiable {
    var id: Int
    var species: FishSpecies
    var x: Double, y: Double, vx: Double, vy: Double
    var phase: Double, depth: Double, yaw: Double
    var finPhase = 0.0
    var activity = 1.0
    var mood: FishMood = .cruise
    var moodRemaining = 6.0
    var appetite = 1.0
    var feeding: FeedingResponse?
    var feedingCooldown = 0.0
}

struct FoodPellet: Identifiable {
    var id: Int
    var x: Double, y: Double
    var age = 0.0
    var releaseDelay = 0.0
    var sinkSpeed = 0.025
    var drift = 0.002
    var phase = 0.0
    var size = 1.0
    var rotation = 0.0
    var spin = 0.0
    var floatDuration = 0.0
}

struct BubbleState {
    var x: Double, y: Double
    var originX: Double, originY: Double
    var age: Double
    var riseSpeed: Double, drift: Double, phase: Double, radius: Double
    var generation = 0
}

struct AquariumSimulation {
    private(set) var fish: [FishState] = []
    private(set) var food: [FoodPellet] = []
    private(set) var pendingFood: [FoodPellet] = []
    private(set) var bubbles: [BubbleState] = []
    private var bubbleRandom = AquariumRandom(state: 901283)
    private var lastDropX: Double?
    private(set) var mealsEaten = 0
    private(set) var time = 0.0
    private var movementTime = 0.0
    private var random: AquariumRandom
    private var nextID = 0
    private var nextFoodID = 0
    private var theme: AquariumTheme?
    var visibleRegion = SwimRegion(left: 0, right: 1, bottom: 0, top: 1)
    init(seed: UInt64 = 42017) {
        random = AquariumRandom(state: seed)
        bubbleRandom = AquariumRandom(state: seed ^ 0xBABB1E)
    }

    static func region(for species: FishSpecies, theme: AquariumTheme) -> SwimRegion {
        if species == .loach {
            switch theme {
            case .grove: return SwimRegion(left: 0.48, right: 0.78, bottom: 0.06, top: 0.115)
            case .river: return SwimRegion(left: 0.14, right: 0.63, bottom: 0.06, top: 0.13)
            case .spring: return SwimRegion(left: 0.26, right: 0.57, bottom: 0.06, top: 0.12)
            }
        }
        let x: (Double, Double)
        switch theme { case .grove: x = (0.43, 0.89); case .river: x = (0.19, 0.77); case .spring: x = (0.09, 0.61) }
        switch species {
        case .pearl: return SwimRegion(left: x.0, right: x.1, bottom: 0.53, top: 0.84)
        case .cherry: return SwimRegion(left: x.0, right: x.1, bottom: 0.27, top: 0.57)
        default: return SwimRegion(left: x.0, right: x.1, bottom: 0.39, top: 0.77)
        }
    }

    mutating func synchronize(_ configuration: AquariumConfiguration) {
        if theme != configuration.theme {
            food.removeAll(); pendingFood.removeAll(); bubbles.removeAll(); lastDropX = nil
            theme = configuration.theme
            for i in fish.indices { fish[i].feeding = nil }
        }
        if configuration.bubbles && bubbles.isEmpty {
            for _ in 0..<14 { bubbles.append(makeBubble()) }
        }
        for species in FishSpecies.allCases {
            let desired = configuration.count(species)
            let currentIDs = fish.filter { $0.species == species }.map(\.id)
            let remove = Set(currentIDs.dropFirst(desired))
            fish.removeAll { remove.contains($0.id) }
            let missing = max(0, desired - currentIDs.count)
            let r = Self.region(for: species, theme: configuration.theme).intersecting(visibleRegion)
            for _ in 0..<missing {
                let direction = random.next() > 0.5 ? 1.0 : -1.0
                fish.append(FishState(id: nextID, species: species,
                    x: random.value(r.left...r.right), y: random.value(r.bottom...r.top),
                    vx: direction * species.cruiseSpeed, vy: 0,
                    phase: random.value(0...(2 * .pi)), depth: random.value(0.70...1.15), yaw: direction > 0 ? 0 : .pi, finPhase: random.value(0...6), moodRemaining: random.value(1...10)))
                nextID += 1
            }
        }
        for i in fish.indices {
            let r = swimmingRegion(for: fish[i], configuration: configuration)
            (fish[i].x, fish[i].y) = r.constrain(x: fish[i].x, y: fish[i].y)
        }
    }

    private func swimmingRegion(for fish: FishState, configuration: AquariumConfiguration) -> SwimRegion {
        var r = Self.region(for: fish.species, theme: configuration.theme)
        if fish.feeding != nil && fish.species != .loach {
            r.bottom = min(r.bottom, 0.20)
            r.top = max(r.top, 0.85)
        }
        return r.intersecting(visibleRegion)
    }

    private mutating func makeBubble(previous: BubbleState? = nil) -> BubbleState {
        let left = visibleRegion.left, width = max(0.001, visibleRegion.right - left)
        let unit: Double
        if let previous {
            unit = ((previous.originX - left) / width + bubbleRandom.value(0.22...0.78)).truncatingRemainder(dividingBy: 1)
        } else { unit = bubbleRandom.next() }
        let x = left + unit * width
        let bottom = visibleRegion.bottom
        let y = bottom + bubbleRandom.value(0.01...0.10) * max(0, visibleRegion.top - bottom)
        let radius = bubbleRandom.value(1.1...3.0)
        return BubbleState(x: x, y: y, originX: x, originY: y,
            age: -bubbleRandom.value(0.2...5.0), riseSpeed: 0.020 + radius * 0.017,
            drift: bubbleRandom.value(0.001...0.003), phase: bubbleRandom.value(0...(2 * .pi)),
            radius: radius, generation: (previous?.generation ?? -1) + 1)
    }

    private mutating func advanceBubbles(_ dt: Double, configuration: AquariumConfiguration) {
        guard configuration.bubbles else { return }
        if bubbles.isEmpty { for _ in 0..<14 { bubbles.append(makeBubble()) } }
        for i in bubbles.indices {
            bubbles[i].age += dt
            guard bubbles[i].age >= 0 else { continue }
            let age = bubbles[i].age
            // Ease into buoyant rise after detaching. Larger bubbles rise faster.
            bubbles[i].y = bubbles[i].originY + (age - 0.18 * (1 - exp(-age / 0.18))) * bubbles[i].riseSpeed
            bubbles[i].x = min(visibleRegion.right, max(visibleRegion.left, bubbles[i].originX
                + (sin(age * 2.1 + bubbles[i].phase) - sin(bubbles[i].phase)) * bubbles[i].drift * (1 - exp(-age * 3))))
            if bubbles[i].y >= visibleRegion.top { bubbles[i] = makeBubble(previous: bubbles[i]) }
        }
    }

    mutating func feed(_ configuration: AquariumConfiguration) {
        guard configuration.mode == .live, configuration.swimmingSpeed > 0, !fish.isEmpty else { return }
        let swimmers = fish.filter { $0.species != .loach }
        let residents = swimmers.isEmpty ? fish : swimmers
        let species: FishSpecies = swimmers.isEmpty ? .loach : .rasbora
        let r = Self.region(for: species, theme: configuration.theme).intersecting(visibleRegion)
        let width = max(0.001, r.right - r.left)
        var sources: [Double] = []
        for batch in 0..<3 {
            var candidate = random.value(r.left...r.right)
            if let last = sources.last ?? lastDropX, abs(candidate - last) < width * 0.20 {
                candidate = r.left + (candidate - r.left + width * 0.45).truncatingRemainder(dividingBy: width)
            }
            // Keep the first sprinkle close enough for an immediate, visible reaction.
            if batch == 0, let nearby = residents.min(by: { abs($0.x-candidate) < abs($1.x-candidate) }) {
                candidate = candidate * 0.7 + nearby.x * 0.3
            }
            sources.append(min(r.right, max(r.left, candidate)))
        }
        lastDropX = sources.last
        let count = min(12, max(0, 36 - food.count - pendingFood.count))
        let dropY = swimmers.isEmpty ? min(visibleRegion.top, r.top + 0.075) : visibleRegion.top
        for i in 0..<count {
            let batch = i / 4
            var pellet = FoodPellet(id: nextFoodID,
                x: min(r.right, max(r.left, sources[batch] + random.value(-0.018...0.018))),
                y: max(r.bottom, dropY - random.value(0...0.016)))
            pellet.releaseDelay = i == 0 ? 0 : Double(batch) * 0.42 + random.value(0.06...0.28)
            pellet.sinkSpeed = random.value(0.017...0.033)
            pellet.drift = random.value(0.0008...0.003)
            pellet.phase = random.value(0...(2 * .pi))
            pellet.size = random.value(0.65...1.15)
            pellet.rotation = random.value(-.pi ... .pi)
            pellet.spin = random.value(-1.4...1.4)
            pellet.floatDuration = random.value(0.12...0.60)
            if pellet.releaseDelay == 0 { food.append(pellet) } else { pendingFood.append(pellet) }
            nextFoodID += 1
        }
    }

    static func angleDifference(_ target: Double, _ current: Double) -> Double {
        atan2(sin(target - current), cos(target - current))
    }

    mutating func step(delta: Double, configuration: AquariumConfiguration) {
        guard configuration.mode == .live, delta.isFinite, delta > 0 else { return }
        let dt = min(delta, 1.0 / 15.0)
        time += dt
        advanceBubbles(dt, configuration: configuration)
        guard configuration.swimmingSpeed > 0 else { return }
        let movement = dt * configuration.swimmingSpeed
        movementTime += movement
        let clock = movementTime
        for i in pendingFood.indices { pendingFood[i].releaseDelay -= dt }
        food.append(contentsOf: pendingFood.filter { $0.releaseDelay <= 0 })
        pendingFood.removeAll { $0.releaseDelay <= 0 }
        for i in food.indices {
            food[i].age += dt
            let sinking = min(1, max(0, (food[i].age - food[i].floatDuration) * 2.0))
            food[i].y = max(0.082, food[i].y - dt * food[i].sinkSpeed * sinking)
            food[i].x += sin(food[i].age * 0.8 + food[i].phase) * dt * food[i].drift
            food[i].rotation += food[i].spin * dt
        }
        food.removeAll { $0.age > 70 || $0.x < visibleRegion.left || $0.x > visibleRegion.right }
        let previous = fish
        for i in fish.indices {
            var f = fish[i]
            let home = Self.region(for: f.species, theme: configuration.theme).intersecting(visibleRegion)
            var r = swimmingRegion(for: f, configuration: configuration)
            f.feedingCooldown = max(0, f.feedingCooldown - dt)
            f.moodRemaining -= movement
            f.appetite = min(1, f.appetite + movement * 0.025)
            if f.moodRemaining <= 0 || (f.mood == .feeding && food.isEmpty) {
                let roll = random.next()
                if roll < (f.species == .pearl ? 0.43 : 0.25) {
                    f.mood = .hover; f.moodRemaining = random.value(2...5)
                } else if roll > 0.92 {
                    f.mood = .dash; f.moodRemaining = random.value(0.65...1.2)
                } else {
                    f.mood = f.species == .loach ? .forage : .cruise
                    f.moodRemaining = random.value(5...12)
                }
            }
            let schooling = f.species == .rasbora || f.species == .cherry
            let groupPhase = f.species == .cherry ? 2.4 : 0.0
            let cx = (r.left + r.right) / 2 + sin(clock * 0.11 + groupPhase) * (r.right - r.left) * 0.29
            let cy = (r.bottom + r.top) / 2 + sin(clock * 0.08 + groupPhase) * (r.top - r.bottom) * 0.23
            var tx = schooling ? cx + cos(f.phase * 2) * 0.045 : (r.left + r.right) / 2 + sin(clock * 0.09 + f.phase) * (r.right - r.left) * 0.42
            var ty = schooling ? cy + sin(f.phase) * 0.07 : (r.bottom + r.top) / 2 + cos(clock * 0.13 + f.phase) * (r.top - r.bottom) * 0.39
            if f.feeding == nil && f.feedingCooldown <= 0 && f.appetite > 0.35 {
                let awareness = f.species == .loach ? 0.13 : 0.36
                let candidates = food.filter { pellet in
                    pellet.x >= home.left && pellet.x <= home.right &&
                    pellet.y >= (f.species == .loach ? home.bottom : 0.20) &&
                    hypot(pellet.x - f.x, (pellet.y - f.y) * 0.55) < awareness
                }
                func score(_ pellet: FoodPellet) -> Double {
                    let claimants = fish.filter { $0.id != f.id && $0.feeding?.targetID == pellet.id }.count
                    return hypot(pellet.x-f.x, (pellet.y-f.y)*0.55) + Double(claimants) * 0.045
                }
                if let pellet = candidates.min(by: { score($0) < score($1) }) {
                    f.feeding = FeedingResponse(targetID: pellet.id, x: pellet.x, y: pellet.y,
                        remaining: random.value(0.15...0.95) + hypot(pellet.x-f.x, (pellet.y-f.y)*0.55) * 1.5)
                }
            }
            var targetFood: Int?
            if var response = f.feeding {
                response.age += dt; response.remaining -= dt
                var beginLeaving = false
                let pellet = food.first { $0.id == response.targetID }
                if response.phase == .noticing || response.phase == .approaching {
                    if let pellet, pellet.y >= r.bottom - 0.015, pellet.x >= r.left, pellet.x <= r.right {
                        response.x = pellet.x; response.y = pellet.y
                        if response.remaining <= 0 && response.phase == .noticing {
                            response.phase = .approaching; response.age = 0
                        }
                    } else { response.phase = .leaving; beginLeaving = true }
                }
                if response.phase == .nibbling && response.remaining <= 0 {
                    response.phase = .leaving; beginLeaving = true
                }
                if beginLeaving {
                    // Scatter gently to individual resting spots before joining the group again.
                    (response.x, response.y) = home.constrain(
                        x: f.x + random.value(-0.09...0.09), y: f.y - random.value(0.045...0.10))
                    let inset = (home.top - home.bottom) * 0.12
                    response.y = min(home.top - inset, max(home.bottom + inset, response.y))
                    response.remaining = random.value(2.5...4.5); response.age = 0
                }
                f.feeding = response
                r = swimmingRegion(for: f, configuration: configuration)
                switch response.phase {
                case .noticing: break
                case .approaching:
                    tx = response.x; ty = min(r.top, max(r.bottom, response.y))
                    targetFood = response.targetID; f.mood = .feeding; f.moodRemaining = 1
                case .nibbling:
                    tx = f.x; ty = f.y; f.mood = .feeding; f.moodRemaining = 1
                case .leaving:
                    tx = response.x; ty = response.y; f.mood = .cruise; f.moodRemaining = 3
                    if response.age > 2 && f.y >= home.bottom && f.y <= home.top && (hypot(tx-f.x, (ty-f.y)*0.65) < 0.025 || response.age > 12) {
                        f.feeding = nil; f.feedingCooldown = random.value(6...10)
                        f.mood = .hover; f.moodRemaining = random.value(2...4)
                    }
                }
            }
            let desiredActivity: Double
            if f.feeding?.phase == .nibbling { desiredActivity = 0.18 }
            else if f.feeding?.phase == .leaving { desiredActivity = 0.7 }
            else {
                switch f.mood {
                case .hover: desiredActivity = 0.035
                case .dash: desiredActivity = 2.5
                case .forage: desiredActivity = 0.42
                case .feeding: desiredActivity = (f.species == .pearl ? 1.8 : 2.7) * (0.92 + f.depth * 0.13)
                case .cruise: desiredActivity = 0.85
                }
            }
            f.activity += (desiredActivity - f.activity) * (1 - exp(-movement * 3.5))
            var dx = tx - f.x, dy = (ty - f.y) * 0.65
            for other in previous where other.id != f.id {
                let sx = f.x - other.x, sy = (f.y - other.y) * 0.65
                let distance = hypot(sx, sy)
                let spacing = (f.species.bodySize * f.depth + other.species.bodySize * other.depth) / 3200 * 0.62
                if distance > 0.00001 && distance < spacing {
                    let force = (1 - distance / spacing) * (f.feeding == nil ? 0.11 : 0.035)
                    dx += sx / distance * force; dy += sy / distance * force
                }
            }
            let distance = max(0.001, hypot(dx, dy))
            let speed = f.species.cruiseSpeed * f.activity * min(1, distance / 0.025)
            let desiredVX = dx / distance * speed, desiredVY = dy / distance * speed
            let response = 1 - exp(-movement * (targetFood == nil ? 1.8 : 3.2))
            f.vx += (desiredVX - f.vx) * response
            f.vy += (desiredVY - f.vy) * response
            // Heading integrates an angle through real front/rear views; it never mirrors the sprite.
            let headingVX = targetFood == nil ? f.vx : desiredVX
            if abs(headingVX) > 0.0015 {
                let targetYaw = (headingVX >= 0 ? 0.0 : Double.pi) + sin(clock * 0.19 + f.phase) * 0.10
                let difference = Self.angleDifference(targetYaw, f.yaw)
                let turn = max(-movement * 1.8, min(movement * 1.8, difference * (1 - exp(-movement * 3))))
                f.yaw += turn
            }
            let alignment = abs(cos(f.yaw))
            f.x += f.vx * movement * (0.28 + 0.72 * alignment)
            f.y += f.vy * movement
            (f.x, f.y) = r.constrain(x: f.x, y: f.y)
            f.finPhase += movement * (2.2 + f.activity * 7.5)
            let mouthX = f.x + cos(f.yaw) * f.species.bodySize * f.depth / 2300 * 0.35
            if let targetFood, let pellet = food.first(where: { $0.id == targetFood }),
               hypot(pellet.x-mouthX, (pellet.y-f.y)*0.55) < 0.016 {
                food.removeAll { $0.id == targetFood }; mealsEaten += 1
                f.appetite = max(0, f.appetite - 0.7)
                f.feeding = FeedingResponse(phase: .nibbling, targetID: nil, x: f.x, y: f.y, remaining: random.value(0.65...1.0))
            }
            fish[i] = f
        }
    }
}
