import Foundation
import Combine

enum AquariumTheme: String, CaseIterable, Codable, Identifiable {
    case grove = "sunken-grove"
    case river = "riverlight"
    case spring = "willow-springs"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grove: return "Sunken Grove"
        case .river: return "Riverlight"
        case .spring: return "Willow Springs"
        }
    }

    var subtitle: String {
        switch self {
        case .grove: return "Sculptural wood and plants in crystal-clear water."
        case .river: return "Clear water, sunlit stones, and room to wander."
        case .spring: return "Clear spring water beneath sunlit willow roots."
        }
    }

    var tag: String {
        switch self {
        case .grove: return "PLANTED & PEACEFUL"
        case .river: return "CLEAR & AIRY"
        case .spring: return "FRESH & TRANQUIL"
        }
    }

    var assetName: String { "\(rawValue)-crystal" }
}

enum AquariumLighting: String, Codable, CaseIterable, Identifiable {
    case system, day, night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Follow Mac"
        case .day: return "Day"
        case .night: return "Night"
        }
    }

    func isNight(systemIsDark: Bool) -> Bool { self == .night || (self == .system && systemIsDark) }
}

enum AquariumMode: String, Codable, CaseIterable { case live, still }

enum RenderQuality: String, Codable, CaseIterable, Identifiable {
    case eco, balanced, smooth

    var id: String { rawValue }

    var fps: Int {
        switch self {
        case .eco: return 15
        case .balanced: return 30
        case .smooth: return 60
        }
    }

    var title: String {
        switch self {
        case .eco: return "Quiet · 15 fps"
        case .balanced: return "Balanced · 30 fps"
        case .smooth: return "Fluid · 60 fps"
        }
    }
}

enum FishSpecies: String, CaseIterable, Codable, Identifiable {
    case rasbora, cherry, pearl, loach, danio, golden, betta, koi, shrimp, crab

    var id: String { rawValue }

    var name: String {
        switch self {
        case .rasbora: return "Harlequin rasbora"
        case .cherry: return "Cherry barb"
        case .pearl: return "Pearl gourami"
        case .loach: return "Kuhli loach"
        case .danio: return "Celestial pearl danio"
        case .golden: return "Golden barb"
        case .betta: return "Blue betta"
        case .koi: return "Kohaku koi"
        case .shrimp: return "Cherry shrimp"
        case .crab: return "Thai micro crab"
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

    var defaultCount: Int {
        switch self {
        case .rasbora: return 12
        case .cherry: return 8
        case .pearl: return 2
        case .loach: return 4
        default: return 0
        }
    }

    /// Sprite edge length in points on a 900-point-tall scene.
    var bodySize: Double {
        switch self {
        case .rasbora: return 65
        case .cherry: return 62
        case .pearl: return 138
        case .loach: return 112
        case .danio: return 46
        case .golden: return 84
        case .betta: return 110
        case .koi: return 188
        case .shrimp: return 58
        case .crab: return 56
        }
    }

    /// Approximate body length in scene widths (the 1935×812 artwork on a 900-point-tall scene
    /// is about 2145 points wide; the body fills most of its square sprite).
    var bodyLength: Double { bodySize * 0.8 / 2145 }

    /// Relaxed swimming speed, in scene widths per unit of simulated movement.
    var cruiseSpeed: Double {
        switch self {
        case .rasbora: return 0.033
        case .cherry: return 0.028
        case .pearl: return 0.024
        case .loach: return 0.015
        case .danio: return 0.030
        case .golden: return 0.032
        case .betta: return 0.017
        case .koi: return 0.03
        case .shrimp: return 0.010
        case .crab: return 0.016
        }
    }

    /// Saved-settings key used before the 1.0 species rename.
    var legacyKey: String {
        switch self {
        case .rasbora: return "cardinal"
        case .cherry: return "ember"
        case .pearl: return "gourami"
        case .loach: return "cory"
        default: return rawValue
        }
    }

    /// How deeply the body curves in a turn. Larger fish curve less; eel-like loaches more.
    var bodyFlexibility: Double {
        switch self {
        case .loach: return 1.3
        case .koi, .pearl, .betta: return 1.0
        default: return 1
        }
    }

    /// Relative turning speed. Small fish flick round several times faster than large ones.
    var turnAgility: Double {
        switch self {
        case .rasbora, .cherry, .danio, .golden: return 2.0
        case .koi: return 0.95
        case .pearl: return 0.85
        case .betta: return 0.9
        case .loach: return 1.15
        // Shrimp pivot on their legs rather than swimming round.
        case .shrimp: return 2.5
        default: return 1
        }
    }

    /// How much sand a resident covers side to side, in scene widths: a crab's legs spread far
    /// wider than its shell.
    var bedFootprint: Double { self == .crab ? bodySize * 1.05 / 2145 : bodyLength }

    /// How much faster than cruise a fish may swim to carry itself through a turn. Eel-like
    /// loaches glide round quickly; others push only a little.
    var turnSurge: Double { self == .loach ? 2.6 : 1.3 }

    /// Tightest routine turn, in body lengths. Long, deep-bodied fish swing wide arcs.
    var turnRadius: Double {
        switch self {
        case .koi: return 0.18
        case .pearl, .loach: return 0.18
        case .betta: return 0.16
        default: return 0.12
        }
    }

    var isInvertebrate: Bool { self == .shrimp || self == .crab }
    var isBottomDweller: Bool { self == .loach || isInvertebrate }
    /// Fish that would eat a shrimp, so shrimp flee from them. Loaches and danios are harmless.
    var huntsShrimp: Bool { [Self.cherry, .golden, .pearl, .betta, .koi].contains(self) }
    var isSchooling: Bool { self == .rasbora || self == .cherry || self == .golden }
    var isSlowGlider: Bool { self == .pearl || self == .betta }
    /// The original four species share a multi-view atlas; newer residents ship a single profile.
    var usesProfileAsset: Bool { ![Self.rasbora, .cherry, .pearl, .loach].contains(self) }

    /// Selects the body shape and appendage motion in `FishRendering`.
    var renderingKind: Float {
        switch self {
        case .danio: return 1
        case .pearl, .betta: return 2
        case .loach: return 3
        case .shrimp: return 4
        case .crab: return 5
        default: return 0
        }
    }
}

struct AquariumConfiguration: Codable, Equatable {
    static let populationLimit = 120
    static let speciesLimit = 30

    var theme: AquariumTheme = .river
    var mode: AquariumMode = .live
    var swimmingSpeed: Double = 0.5
    var plantSway: Double = 0.55
    var shimmer: Double = 0.2
    var brightness: Double = 1.0
    // Optional storage lets older preferences decode without losing existing settings.
    var lighting: AquariumLighting? = nil
    var feedingShortcutEnabled: Bool? = nil
    var bubbles = false
    var particles = false
    var quality: RenderQuality = .balanced
    var allDisplays = true
    var wallpaperEnabled = true
    var counts: [String: Int] = Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map { ($0.rawValue, $0.defaultCount) })

    var usesGlobalFeedingShortcut: Bool { feedingShortcutEnabled ?? true }
    var lightingMode: AquariumLighting { lighting ?? .system }
    var totalFish: Int { FishSpecies.allCases.reduce(0) { $0 + count($1) } }

    func count(_ species: FishSpecies) -> Int {
        counts[species.rawValue] ?? counts[species.legacyKey] ?? species.defaultCount
    }

    mutating func setCount(_ species: FishSpecies, _ count: Int) {
        let available = max(0, Self.populationLimit - (totalFish - self.count(species)))
        counts[species.rawValue] = min(available, min(Self.speciesLimit, max(0, count)))
    }

    mutating func sanitize() {
        swimmingSpeed = bounded(swimmingSpeed, 0...2, fallback: 0.5)
        plantSway = bounded(plantSway, 0...1, fallback: 0.55)
        shimmer = bounded(shimmer, 0...1, fallback: 0.2)
        brightness = bounded(brightness, 0.4...1.3, fallback: 1)
        var remaining = Self.populationLimit
        counts = Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map {
            let value = min(remaining, min(Self.speciesLimit, max(0, count($0))))
            remaining -= value
            return ($0.rawValue, value)
        })
    }
}

private func bounded(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
    value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
}

@MainActor final class AquariumStore: ObservableObject {
    private static let storageKey = "aquarium.configuration.v1"
    private static let feedingCooldown: TimeInterval = 3

    @Published var configuration: AquariumConfiguration {
        didSet {
            if let data = try? JSONEncoder().encode(configuration) { defaults?.set(data, forKey: Self.storageKey) }
        }
    }
    @Published var message: String? = nil
    @Published var feedingShortcutAvailable = false
    let feedRequests = PassthroughSubject<Void, Never>()
    private var lastFeed = -Double.infinity
    private let defaults: UserDefaults?

    var canFeed: Bool {
        configuration.mode == .live && configuration.swimmingSpeed > 0 && configuration.totalFish > 0
    }

    init(persist: Bool = true) {
        defaults = persist ? UserDefaults.standard : nil
        var initial = AquariumConfiguration()
        if let data = defaults?.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(AquariumConfiguration.self, from: data) { initial = stored }
        initial.sanitize()
        configuration = initial
    }

    func requestFeed() {
        guard canFeed else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFeed > Self.feedingCooldown else { return }
        lastFeed = now
        feedRequests.send()
        message = "Food is in the water. Watch your fish turn and gather."
    }

    func restoreDefaults() { configuration = AquariumConfiguration() }
}
