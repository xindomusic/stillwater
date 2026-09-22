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
    case rasbora, cherry, pearl, loach, danio, golden, betta, koi, shrimp, crab
    var id: String { rawValue }
    var name: String {
        switch self {
        case .rasbora: return "Harlequin rasbora"; case .cherry: return "Cherry barb"
        case .pearl: return "Pearl gourami"; case .loach: return "Kuhli loach"
        case .danio: return "Celestial pearl danio"; case .golden: return "Golden barb"
        case .betta: return "Blue betta"; case .koi: return "Kohaku koi"
        case .shrimp: return "Cherry shrimp"; case .crab: return "Thai micro crab"
        }
    }
    var detail: String {
        switch self {
        case .rasbora: return "Small · copper & charcoal · gentle school"
        case .cherry: return "Small · cherry red · curious explorer"
        case .pearl: return "Large · pearlescent · unhurried glider"
        case .loach: return "Medium · gold & brown · sand forager"
        case .danio: return "Tiny · midnight blue & pearl spots"
        case .golden: return "Medium · golden yellow · lively swimmer"
        case .betta: return "Medium · cobalt blue · flowing fins"
        case .koi: return "Large · ivory & vermilion · slow cruiser"
        case .shrimp: return "Tiny · scarlet red · gentle grazer"
        case .crab: return "Tiny · silvery sand · sideways explorer"
        }
    }
    var defaultCount: Int { switch self { case .rasbora: return 12; case .cherry: return 8; case .pearl: return 2; case .loach: return 4; default: return 0 } }
    var bodySize: Double { switch self { case .rasbora: return 65; case .cherry: return 62; case .pearl: return 138; case .loach: return 112; case .danio: return 46; case .golden: return 84; case .betta: return 110; case .koi: return 188; case .shrimp: return 58; case .crab: return 56 } }
    var cruiseSpeed: Double { switch self { case .rasbora: return 0.033; case .cherry: return 0.028; case .pearl: return 0.017; case .loach: return 0.015; case .danio: return 0.030; case .golden: return 0.032; case .betta: return 0.015; case .koi: return 0.018; case .shrimp: return 0.010; case .crab: return 0.008 } }
    var legacyKey: String { switch self { case .rasbora: return "cardinal"; case .cherry: return "ember"; case .pearl: return "gourami"; case .loach: return "cory"; default: return rawValue } }
    var isInvertebrate: Bool { self == .shrimp || self == .crab }
    var isBottomDweller: Bool { self == .loach || isInvertebrate }
    var usesProfileAsset: Bool { ![Self.rasbora, .cherry, .pearl, .loach].contains(self) }
    var renderingKind: Float { switch self { case .danio: return 1; case .pearl, .betta: return 2; case .loach: return 3; case .shrimp: return 4; case .crab: return 5; default: return 0 } }

}

struct AquariumConfiguration: Codable, Equatable {
    static let populationLimit = 120
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
    mutating func setCount(_ species: FishSpecies, _ count: Int) {
        let available = max(0, Self.populationLimit - (totalFish - self.count(species)))
        counts[species.rawValue] = min(available, min(30, max(0, count)))
    }
    mutating func sanitize() {
        swimmingSpeed = bounded(swimmingSpeed, 0...2, fallback: 0.5)
        plantSway = bounded(plantSway, 0...1, fallback: 0.55)
        shimmer = bounded(shimmer, 0...1, fallback: 0.2)
        brightness = bounded(brightness, 0.4...1.3, fallback: 1)
        var remaining = Self.populationLimit
        counts = Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map {
            let value = min(remaining, min(30, max(0, count($0))))
            remaining -= value
            return ($0.rawValue, value)
        })
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
    var depth: Double, yaw: Double
    var yawVelocity = 0.0
    var finPhase = 0.0
    var stroke = FishStroke(seed: 1)
    var navigation = FishNavigation(seed: 1, heading: 0)
    var behaviorRandom = AquariumRandom(state: 1)
    var pitch = 0.0
    var activity = 1.0
    var mood: FishMood = .cruise
    var moodRemaining = 6.0
    var appetite = 1.0
    var feeding: FeedingResponse?
    var feedingCooldown = 0.0
    var shrimpBehavior = ShrimpBehavior(seed: 1)

    var spineCurve: SIMD4<Float> {
        species.isInvertebrate ? .zero : stroke.spineCurve(phase: finPhase, species: species)
    }

    /// Fish keep a modest nose-up/down attitude. Rest and yaw turns level the body.
    static func pitchTarget(species: FishSpecies, vx: Double, vy: Double, yawRate: Double) -> Double {
        guard !species.isInvertebrate else { return 0 }
        let limit = species.isBottomDweller ? 0.08 : 0.22
        let moving = min(1, hypot(vx, vy) / 0.006)
        let turning = 1 / (1 + abs(yawRate) * 2.5)
        return max(-limit, min(limit, atan2(vy * 0.42, max(0.008, abs(vx))))) * moving * turning
    }

    static func forwardTravel(vx: Double, yaw: Double) -> Double {
        max(0, cos(yaw) * (vx < 0 ? -1 : 1))
    }
}

enum ShrimpPhase: String, CaseIterable { case grazing, drifting, seekingCover, hidden, emerging }

/// Each shrimp alternates open exploration with a refuge near a planted edge.
struct ShrimpBehavior {
    private var random: AquariumRandom
    private(set) var phase: ShrimpPhase = .grazing
    private(set) var remaining: Double
    private(set) var target = SIMD2<Double>(0.5, 0.1)
    private(set) var concealment = 0.0
    private(set) var coverOnLeft = false
    init(seed: UInt64) {
        random = AquariumRandom(state: seed)
        remaining = random.value(3...11)
    }
    var holdsPosition: Bool { phase == .hidden || phase == .emerging }
    var activity: Double {
        switch phase { case .grazing: return 0.32; case .drifting: return 1.25; case .seekingCover: return 1.05; case .hidden, .emerging: return 0.01 }
    }
    mutating func advance(delta: Double, x: Double, y: Double, region: SwimRegion, feeding: Bool) {
        let bedTop = region.bottom + (region.top - region.bottom) * 0.46
        if feeding {
            if phase != .grazing { phase = .grazing; remaining = random.value(5...12) }
            concealment = max(0, concealment - delta * 0.65)
            return
        }
        remaining -= delta
        if phase == .seekingCover && hypot(x - target.x, (y - target.y) * 0.65) < 0.014 {
            phase = .hidden; remaining = random.value(3...9)
        } else if remaining <= 0 {
            switch phase {
            case .hidden: phase = .emerging; remaining = 2.2
            case .grazing where random.next() < 0.55, .emerging:
                phase = .drifting; remaining = random.value(5...12)
                target = SIMD2(random.value((region.left + (region.right - region.left) * 0.18)...(region.right - (region.right - region.left) * 0.18)), random.value(bedTop...region.top))
            case .grazing, .drifting:
                phase = .seekingCover; remaining = random.value(35...55)
                coverOnLeft = random.next() < 0.5
                target = SIMD2(coverOnLeft ? region.left + 0.012 : region.right - 0.012, bedTop - 0.006)
                (target.x, target.y) = region.constrain(x: target.x, y: target.y)
            case .seekingCover:
                phase = .grazing; remaining = random.value(4...10)
            }
        }
        let hiding = phase == .hidden
        concealment = max(0, min(1, concealment + delta * (hiding ? 0.6 : -0.65)))
    }
}

/// A fish chooses intentions at irregular intervals; velocity and posture ease toward them.
struct FishNavigation {
    private var random: AquariumRandom
    private(set) var heading: Double
    private(set) var remaining: Double
    private(set) var speedFactor = 1.0
    private(set) var turnLimit = 1.2
    private(set) var viewAngle = 0.0
    private(set) var shoalAffinity = 0.15
    private(set) var decisions = 0
    private(set) var lastTurn = 0.0

    init(seed: UInt64, heading: Double) {
        random = AquariumRandom(state: seed)
        self.heading = heading
        remaining = random.value(0.4...2.5)
        speedFactor = random.value(0.65...1.20)
        turnLimit = random.value(0.65...1.8)
        viewAngle = random.value(-0.32...0.32)
    }

    mutating func advance(delta: Double, x: Double, y: Double, region: SwimRegion, resting: Bool) {
        guard delta > 0 else { return }
        remaining -= delta
        guard !resting else { return }
        let marginX = min(0.055, (region.right - region.left) * 0.18)
        let marginY = min(0.04, (region.top - region.bottom) * 0.22)
        let approachingEdge = (x < region.left + marginX && cos(heading) < -0.2)
            || (x > region.right - marginX && cos(heading) > 0.2)
            || (y < region.bottom + marginY && sin(heading) < -0.2)
            || (y > region.top - marginY && sin(heading) > 0.2)
        guard remaining <= 0 || approachingEdge else { return }
        let old = heading
        if approachingEdge {
            heading = atan2(((region.bottom + region.top) / 2 - y) * 0.65, (region.left + region.right) / 2 - x) + random.value(-0.35...0.35)
        } else {
            let choice = random.next()
            let degrees = choice < 0.62 ? random.value(10...45) : (choice < 0.88 ? random.value(45...100) : random.value(140...180))
            heading += degrees * .pi / 180 * (random.next() < 0.5 ? -1 : 1)
        }
        heading = atan2(sin(heading), cos(heading))
        lastTurn = AquariumSimulation.angleDifference(heading, old)
        decisions += 1
        remaining = random.value(0.8...3.8)
        speedFactor = random.value(0.50...1.30)
        turnLimit = random.value(0.55...1.8)
        viewAngle = random.value(-0.52...0.52)
        shoalAffinity = random.next() < 0.35 ? 0 : random.value(0.08...0.30)
    }
}

/// Independent, smoothly changing motor rhythms; this stream never changes navigation or feeding decisions.
struct FishStroke {
    private var random: AquariumRandom
    private var remaining = 0.0
    private var cadenceTarget = 1.0
    private var strengthTarget = 1.0
    private var finTarget = 1.0
    private var coasting = false
    private var cadence = 1.0
    private var strength = 1.0
    private var finEnergy = 1.0
    private(set) var tailRate = 7.0
    private(set) var amplitude = 0.5
    private(set) var pectoralPhase: Double
    private(set) var dorsalPhase: Double
    private(set) var finAmplitude = 0.5
    private(set) var spread = 0.5
    private(set) var bend = 0.0

    init(seed: UInt64) {
        random = AquariumRandom(state: seed)
        pectoralPhase = random.value(0...(2 * .pi))
        dorsalPhase = random.value(0...(2 * .pi))
        remaining = random.value(0.2...1.4)
        cadence = random.value(0.85...1.15); cadenceTarget = cadence
    }

    func spineCurve(phase: Double, species: FishSpecies) -> SIMD4<Float> {
        let power = amplitude * (species == .loach ? 0.25 : 0.18)
        let wave = sin(phase), follow = sin(phase - 1.4)
        return SIMD4(Float(-bend * 0.34 + power * wave),
            Float(power * (follow - wave) * 1.6), Float(-power * follow * 0.65), 0)
    }

    mutating func advance(delta: Double, species: FishSpecies, speed: Double, acceleration: Double, turnRate: Double) {
        guard delta > 0 else { return }
        remaining -= delta
        if remaining <= 0 {
            coasting = !coasting && random.next() < (species == .loach ? 0.20 : 0.48)
            remaining = coasting ? random.value(0.35...1.15) : random.value(0.65...2.6)
            cadenceTarget = random.value(0.78...1.22)
            strengthTarget = coasting ? random.value(0.12...0.28) : random.value(0.75...1.15)
            finTarget = random.value(0.65...1.25)
        }
        let ease = 1 - exp(-delta * 3.8)
        cadence += (cadenceTarget - cadence) * ease
        strength += (strengthTarget - strength) * ease
        finEnergy += (finTarget - finEnergy) * ease
        // Acceleration and steering recruit strokes even during a planned glide.
        let effort = min(1, max(0, acceleration) * 0.32 + abs(turnRate) * 0.23 + max(0, speed - 1.1) * 0.55)
        let drive = max(strength, effort)
        let speciesRate: Double = species == .pearl ? 0.70 : (species == .loach ? 0.82 : 1)
        let rate = (2.1 + min(2.5, speed) * 6.3) * speciesRate * cadence * (0.48 + drive * 0.52)
        tailRate += (rate - tailRate) * ease
        let power = min(1.25, (0.06 + min(2.5, speed) * 0.44 + effort * 0.23) * drive)
        amplitude += (power - amplitude) * ease
        // Hovering uses gentle balancing fins even while the tail nearly rests.
        let balance = min(1.15, (0.48 + 0.30 / (1 + speed) + abs(turnRate) * 0.15) * finEnergy)
        finAmplitude += (balance - finAmplitude) * ease
        pectoralPhase += delta * (5.1 + speed * 1.7) * (0.75 + finEnergy * 0.25)
        dorsalPhase += delta * (2.3 + speed * 1.1) * (1.18 - cadence * 0.18)
        spread += (min(1, 0.28 + balance * 0.52 + effort * 0.16) - spread) * ease
        bend += (max(-0.85, min(0.85, turnRate * 0.38)) - bend) * ease
    }
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
    var depth = 1.0
    var tumble = 0.0
    var tumbleSpeed = 0.0
}

struct BubbleState {
    var x: Double, y: Double
    var originX: Double, originY: Double
    var age: Double
    var riseSpeed: Double, drift: Double, phase: Double, radius: Double
    var generation = 0
    var depth = 1.0
    var randomState: UInt64 = 1
    var depthBand = 0
}

// Shares the fish's depth axis: larger values are closer to the viewer.
enum ParticlePerspective {
    static func scale(_ depth: Double) -> Double { pow(depth, 1.45) }
    static func layer(_ depth: Double) -> Double { 5 + depth }
    static func distance(band: Int, fraction: Double) -> Double {
        [0.55, 0.87, 1.24][band % 3] + fraction * 0.15
    }
}

struct AquariumSimulation {
    private(set) var fish: [FishState] = []
    private(set) var food: [FoodPellet] = []
    private(set) var pendingFood: [FoodPellet] = []
    private(set) var bubbles: [BubbleState] = []
    private let entitySeed: UInt64
    private var nextBubbleID: UInt64 = 0
    private var nextBubbleBand = 0
    private var lastDropX: Double?
    private(set) var mealsEaten = 0
    private(set) var time = 0.0
    private var random: AquariumRandom
    private var nextID = 0
    private var nextFoodID = 0
    private var neighbors: [(id: Int, species: FishSpecies, x: Double, y: Double, vx: Double, vy: Double, size: Double)] = []
    private var theme: AquariumTheme?
    var visibleRegion = SwimRegion(left: 0, right: 1, bottom: 0, top: 1)
    init(seed: UInt64 = 42017) {
        random = AquariumRandom(state: seed)
        entitySeed = seed
    }

    static func region(for species: FishSpecies, theme: AquariumTheme) -> SwimRegion {
        if species.isBottomDweller {
            var bed: SwimRegion
            switch theme {
            case .grove: bed = SwimRegion(left: 0.48, right: 0.78, bottom: 0.06, top: 0.115)
            case .river: bed = SwimRegion(left: 0.14, right: 0.63, bottom: 0.06, top: 0.13)
            case .spring: bed = SwimRegion(left: 0.26, right: 0.57, bottom: 0.06, top: 0.12)
            }
            if species == .shrimp { bed.top += 0.08 }
            return bed
        }
        let x: (Double, Double)
        switch theme { case .grove: x = (0.43, 0.89); case .river: x = (0.19, 0.77); case .spring: x = (0.09, 0.61) }
        switch species {
        case .pearl, .betta: return SwimRegion(left: x.0, right: x.1, bottom: 0.53, top: 0.84)
        case .koi: return SwimRegion(left: x.0 + 0.025, right: x.1 - 0.025, bottom: 0.32, top: 0.66)
        case .cherry: return SwimRegion(left: x.0, right: x.1, bottom: 0.27, top: 0.57)
        default: return SwimRegion(left: x.0, right: x.1, bottom: 0.39, top: 0.77)
        }
    }

    mutating func synchronize(_ configuration: AquariumConfiguration) {
        if theme != configuration.theme {
            food.removeAll(); pendingFood.removeAll(); bubbles.removeAll(); lastDropX = nil
            theme = configuration.theme
            for i in fish.indices {
                fish[i].feeding = nil
                fish[i].shrimpBehavior = ShrimpBehavior(seed: entitySeed ^ UInt64(fish[i].id) ^ 0x5A11)
            }
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
                let personalSeed = entitySeed ^ (UInt64(nextID) &* 0x9E3779B97F4A7C15)
                var birthRandom = AquariumRandom(state: personalSeed ^ 0xB17A)
                let direction = birthRandom.next() > 0.5 ? 1.0 : -1.0
                fish.append(FishState(id: nextID, species: species,
                    x: birthRandom.value(r.left...r.right), y: birthRandom.value(r.bottom...r.top),
                    vx: direction * species.cruiseSpeed, vy: 0,
                    depth: birthRandom.value(0.70...1.15), yaw: species == .crab || direction > 0 ? 0 : .pi, finPhase: birthRandom.value(0...6), moodRemaining: birthRandom.value(1...10)))
                fish[fish.count - 1].stroke = FishStroke(seed: personalSeed ^ 0xF1A5)
                fish[fish.count - 1].navigation = FishNavigation(seed: personalSeed ^ 0xA11CE, heading: direction > 0 ? 0 : .pi)
                fish[fish.count - 1].behaviorRandom = AquariumRandom(state: personalSeed ^ 0xBEA710)
                fish[fish.count - 1].shrimpBehavior = ShrimpBehavior(seed: personalSeed ^ 0x5A11)
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
        if fish.feeding != nil && !fish.species.isBottomDweller {
            r.bottom = min(r.bottom, 0.20)
            r.top = max(r.top, 0.85)
        }
        return r.intersecting(visibleRegion)
    }

    private mutating func makeBubble(previous: BubbleState? = nil) -> BubbleState {
        var bubbleRandom = AquariumRandom(state: previous?.randomState ?? (entitySeed ^ (nextBubbleID &* 0x9E3779B97F4A7C15) ^ 0xBABB1E))
        if previous == nil { nextBubbleID += 1 }
        let left = visibleRegion.left, width = max(0.001, visibleRegion.right - left)
        let unit: Double
        if let previous {
            unit = ((previous.originX - left) / width + bubbleRandom.value(0.22...0.78)).truncatingRemainder(dividingBy: 1)
        } else { unit = bubbleRandom.next() }
        let x = left + unit * width
        let bottom = visibleRegion.bottom
        let y = bottom + bubbleRandom.value(0.01...0.10) * max(0, visibleRegion.top - bottom)
        let radius = bubbleRandom.value(1.1...3.0)
        let band = previous.map { ($0.depthBand + 1) % 3 } ?? nextBubbleBand
        let depth = ParticlePerspective.distance(band: band, fraction: bubbleRandom.next())
        if previous == nil { nextBubbleBand = (nextBubbleBand + 1) % 3 }
        return BubbleState(x: x, y: y, originX: x, originY: y,
            age: -bubbleRandom.value(0.2...5.0), riseSpeed: (0.020 + radius * 0.017) * ParticlePerspective.scale(depth),
            drift: bubbleRandom.value(0.001...0.003) * ParticlePerspective.scale(depth), phase: bubbleRandom.value(0...(2 * .pi)),
            radius: radius, generation: (previous?.generation ?? -1) + 1, depth: depth, randomState: bubbleRandom.state, depthBand: band)
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
        let swimmers = fish.filter { !$0.species.isBottomDweller }
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
            var pelletRandom = AquariumRandom(state: entitySeed ^ (UInt64(nextFoodID) &* 0x9E3779B97F4A7C15) ^ 0xF00D)
            var pellet = FoodPellet(id: nextFoodID,
                x: min(r.right, max(r.left, sources[batch] + pelletRandom.value(-0.018...0.018))),
                y: max(r.bottom, dropY - pelletRandom.value(0...0.016)))
            pellet.releaseDelay = i == 0 ? 0 : Double(batch) * 0.42 + pelletRandom.value(0.06...0.28)
            pellet.sinkSpeed = pelletRandom.value(0.017...0.033)
            pellet.drift = pelletRandom.value(0.0008...0.003)
            pellet.phase = pelletRandom.value(0...(2 * .pi))
            pellet.size = pelletRandom.value(0.65...1.15)
            pellet.rotation = pelletRandom.value(-.pi ... .pi)
            pellet.spin = pelletRandom.value(-1.4...1.4)
            pellet.floatDuration = pelletRandom.value(0.12...0.60)
            pellet.depth = ParticlePerspective.distance(band: nextFoodID, fraction: pelletRandom.next())
            pellet.tumble = pelletRandom.value(-.pi ... .pi)
            pellet.tumbleSpeed = pelletRandom.value(0.35...0.85)
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
        for i in pendingFood.indices { pendingFood[i].releaseDelay -= dt }
        food.append(contentsOf: pendingFood.filter { $0.releaseDelay <= 0 })
        pendingFood.removeAll { $0.releaseDelay <= 0 }
        for i in food.indices {
            food[i].age += dt
            let sinking = min(1, max(0, (food[i].age - food[i].floatDuration) * 2.0))
            food[i].y = max(0.082, food[i].y - dt * food[i].sinkSpeed * sinking)
            food[i].x += sin(food[i].age * 0.8 + food[i].phase) * dt * food[i].drift
            let settling = min(1, max(0, (food[i].y - 0.082) / 0.025))
            food[i].rotation += food[i].spin * dt * settling
            food[i].tumble += food[i].tumbleSpeed * dt * settling
        }
        food.removeAll { $0.age > 70 || $0.x < visibleRegion.left || $0.x > visibleRegion.right }
        neighbors.removeAll(keepingCapacity: true)
        for f in fish { neighbors.append((f.id, f.species, f.x, f.y, f.vx, f.vy, f.species.bodySize * f.depth)) }
        for i in fish.indices {
            var f = fish[i]
            let home = Self.region(for: f.species, theme: configuration.theme).intersecting(visibleRegion)
            var r = swimmingRegion(for: f, configuration: configuration)
            f.feedingCooldown = max(0, f.feedingCooldown - dt)
            f.moodRemaining -= movement
            f.appetite = min(1, f.appetite + movement * 0.025)
            if f.moodRemaining <= 0 || (f.mood == .feeding && food.isEmpty) {
                let roll = f.behaviorRandom.next()
                if roll < (f.species == .pearl || f.species == .betta || f.species.isInvertebrate ? 0.43 : 0.25) {
                    f.mood = .hover; f.moodRemaining = f.behaviorRandom.value(2...5)
                } else if roll > 0.92 && !f.species.isInvertebrate {
                    f.mood = .dash; f.moodRemaining = f.behaviorRandom.value(0.65...1.2)
                } else {
                    f.mood = f.species.isBottomDweller ? .forage : .cruise
                    f.moodRemaining = f.behaviorRandom.value(5...12)
                }
            }
            let schooling = f.species == .rasbora || f.species == .cherry || f.species == .golden
            if f.feeding == nil {
                f.navigation.advance(delta: movement, x: f.x, y: f.y, region: home, resting: f.mood == .hover)
            }
            let lookAhead = 0.075
            var (tx, ty) = r.constrain(x: f.x + cos(f.navigation.heading) * lookAhead,
                y: f.y + sin(f.navigation.heading) * lookAhead / 0.65)
            if f.feeding == nil && f.feedingCooldown <= 0 && f.appetite > 0.35 {
                let awareness = f.species.isBottomDweller ? 0.13 : 0.36
                var closest: FoodPellet?
                var bestScore = Double.infinity
                for pellet in food where pellet.x >= home.left && pellet.x <= home.right && pellet.y >= (f.species.isBottomDweller ? home.bottom : 0.20) {
                    let distance = hypot(pellet.x - f.x, (pellet.y - f.y) * 0.55)
                    guard distance < awareness else { continue }
                    let claimants = fish.reduce(0) { $0 + (($1.id != f.id && $1.feeding?.targetID == pellet.id) ? 1 : 0) }
                    let score = distance + Double(claimants) * 0.045
                    if score < bestScore { bestScore = score; closest = pellet }
                }
                if let pellet = closest {
                    f.feeding = FeedingResponse(targetID: pellet.id, x: pellet.x, y: pellet.y,
                        remaining: f.behaviorRandom.value(0.15...0.95) + hypot(pellet.x-f.x, (pellet.y-f.y)*0.55) * 1.5)
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
                        x: f.x + f.behaviorRandom.value(-0.09...0.09), y: f.y - f.behaviorRandom.value(f.species.isBottomDweller ? 0.004...0.012 : 0.045...0.10))
                    let inset = (home.top - home.bottom) * 0.12
                    response.y = min(home.top - inset, max(home.bottom + inset, response.y))
                    response.remaining = f.behaviorRandom.value(2.5...4.5); response.age = 0
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
                        f.feeding = nil; f.feedingCooldown = f.behaviorRandom.value(6...10)
                        f.mood = .hover; f.moodRemaining = f.behaviorRandom.value(2...4)
                    }
                }
            }
            let desiredActivity: Double
            if f.species == .shrimp {
                f.shrimpBehavior.advance(delta: movement, x: f.x, y: f.y, region: home, feeding: f.feeding != nil)
                if f.feeding == nil {
                    switch f.shrimpBehavior.phase {
                    case .grazing: ty = min(ty, home.bottom + (home.top - home.bottom) * 0.46)
                    case .drifting, .seekingCover: tx = f.shrimpBehavior.target.x; ty = f.shrimpBehavior.target.y
                    case .hidden, .emerging: tx = f.x; ty = f.y
                    }
                }
            }
            if f.species == .shrimp && f.feeding == nil { desiredActivity = f.shrimpBehavior.activity }
            else if f.feeding?.phase == .nibbling { desiredActivity = 0.18 }
            else if f.feeding?.phase == .leaving { desiredActivity = 0.7 }
            else {
                switch f.mood {
                case .hover: desiredActivity = 0.035
                case .dash: desiredActivity = 2.5
                case .forage: desiredActivity = 0.42
                case .feeding: desiredActivity = (f.species.isInvertebrate ? 1.25 : (f.species == .pearl || f.species == .betta ? 1.8 : 2.7)) * (0.92 + f.depth * 0.13)
                case .cruise: desiredActivity = 0.85
                }
            }
            f.activity += (desiredActivity - f.activity) * (1 - exp(-movement * 3.5))
            var dx = tx - f.x, dy = (ty - f.y) * 0.65
            var shoalX = 0.0, shoalY = 0.0, shoalVX = 0.0, shoalVY = 0.0, shoalCount = 0.0
            for other in neighbors where other.id != f.id {
                let sx = f.x - other.x, sy = (f.y - other.y) * 0.65
                let squaredDistance = sx * sx + sy * sy
                if schooling && f.feeding == nil && other.species == f.species && squaredDistance < 0.0225 {
                    shoalX -= sx; shoalY -= sy; shoalVX += other.vx; shoalVY += other.vy; shoalCount += 1
                }
                let spacing = (f.species.bodySize * f.depth + other.size) / 3200 * 0.62
                if squaredDistance > 0.0000000001 && squaredDistance < spacing * spacing {
                    let distance = sqrt(squaredDistance)
                    let force = (1 - distance / spacing) * (f.feeding == nil ? 0.11 : 0.035)
                    dx += sx / distance * force; dy += sy / distance * force
                }
            }
            if shoalCount > 0 {
                let affinity = f.navigation.shoalAffinity / shoalCount
                dx += (shoalX + shoalVX * 0.35) * affinity
                dy += (shoalY + shoalVY * 0.35) * affinity
            }
            let distance = max(0.001, hypot(dx, dy))
            let speed = f.species.cruiseSpeed * f.activity * (f.feeding == nil ? f.navigation.speedFactor : 1) * min(1, distance / 0.025)
            let desiredVX = dx / distance * speed, desiredVY = dy / distance * speed
            let previousSpeed = hypot(f.vx, f.vy)
            let previousYaw = f.yaw
            let response = 1 - exp(-movement * (targetFood == nil ? 1.8 : 3.2))
            f.vx += (desiredVX - f.vx) * response
            f.vy += (desiredVY - f.vy) * response
            if f.species == .shrimp && f.feeding == nil && f.shrimpBehavior.holdsPosition {
                f.vx *= exp(-movement * 12); f.vy *= exp(-movement * 12)
            }
            // Heading integrates an angle through real front/rear views; it never mirrors the sprite.
            let headingVX = desiredVX
            var requestedTurnRate = 0.0
            if f.species == .crab {
                let crawlHeading = atan2(desiredVY, desiredVX)
                let targetYaw = sin(crawlHeading) * 0.35 + f.navigation.viewAngle * 0.5
                requestedTurnRate = max(-0.65, min(0.65, Self.angleDifference(targetYaw, f.yaw) * 1.8))
            } else if abs(headingVX) > 0.0015 && abs(headingVX) / max(0.003, hypot(f.vx, f.vy * 0.45)) > 0.25 {
                let targetYaw = (headingVX >= 0 ? 0.0 : Double.pi) + (f.feeding == nil ? f.navigation.viewAngle : 0)
                let difference = Self.angleDifference(targetYaw, f.yaw)
                let turnLimit = f.feeding == nil ? f.navigation.turnLimit : 1.8
                requestedTurnRate = max(-turnLimit, min(turnLimit, difference * 2.5))
            }
            f.yawVelocity += (requestedTurnRate - f.yawVelocity) * (1 - exp(-movement * 10))
            f.yaw += f.yawVelocity * movement
            let pitchTarget = FishState.pitchTarget(species: f.species, vx: f.vx, vy: f.vy, yawRate: f.yawVelocity)
            let pitchStep = (pitchTarget - f.pitch) * (1 - exp(-movement * 3.0))
            f.pitch += max(-movement * 0.35, min(movement * 0.35, pitchStep))
            // A reversal turns the head first. Never translate tail-first while yaw catches up.
            let alignment = f.species == .crab ? 1 : FishState.forwardTravel(vx: f.vx, yaw: f.yaw)
            f.x += f.vx * movement * alignment
            f.y += f.vy * movement
            (f.x, f.y) = r.constrain(x: f.x, y: f.y)
            let actualSpeed = hypot(f.vx, f.vy)
            f.stroke.advance(delta: movement, species: f.species, speed: actualSpeed / f.species.cruiseSpeed,
                acceleration: (actualSpeed - previousSpeed) / (movement * f.species.cruiseSpeed),
                turnRate: Self.angleDifference(f.yaw, previousYaw) / movement)
            // Reverse a crab's gait clock continuously as travel changes direction;
            // switching the sign inside the shader would snap all eight feet.
            let gaitDirection = f.species == .crab ? max(-1, min(1, (f.vx + f.vy * 0.45) / f.species.cruiseSpeed * 3)) : 1
            f.finPhase += movement * f.stroke.tailRate * gaitDirection
            let mouthX = f.x + (f.species == .crab ? 0 : cos(f.yaw) * f.species.bodySize * f.depth / 2300 * (f.species == .shrimp ? 0.18 : 0.35))
            if let targetFood, let pellet = food.first(where: { $0.id == targetFood }),
               hypot(pellet.x-mouthX, (pellet.y-f.y)*0.55) < 0.016 {
                food.removeAll { $0.id == targetFood }; mealsEaten += 1
                f.appetite = max(0, f.appetite - 0.7)
                f.feeding = FeedingResponse(phase: .nibbling, targetID: nil, x: f.x, y: f.y, remaining: f.behaviorRandom.value(0.65...1.0))
            }
            fish[i] = f
        }
    }
}
