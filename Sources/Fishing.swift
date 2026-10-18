import Foundation

// Fishing: tackle, what each resident thinks of it, the rig in the water, and the catch log.
// Pure model code (Foundation only), so every cast, bite, and fight replays in tests.

/// Hooks differ the way real ones do: a small, fine-wire hook fits small mouths and hides in the
/// bait but opens out under a strong fish; a circle hook is strong and sets itself as the fish turns.
enum HookKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case fine, jHook, circle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fine: return "No. 18 fine wire"
        case .jHook: return "No. 12 J-hook"
        case .circle: return "No. 6 circle hook"
        }
    }

    var shortTitle: String {
        switch self {
        case .fine: return "Fine #18"
        case .jHook: return "J-hook #12"
        case .circle: return "Circle #6"
        }
    }

    var detail: String {
        switch self {
        case .fine: return "Tiny and nearly invisible: the hook for small mouths. Light, so play a big fish gently or it opens out."
        case .jHook: return "For gouramis and other mid-sized mouths. Strike when the float slides under."
        case .circle: return "For koi. Sets itself as the fish turns, so don't strike, and almost never comes out. Holds bait well; small fish just pick at it."
        }
    }

    /// Drawn length in points on a 900-point-tall scene. Hooks are drawn against the fish rather
    /// than the tank's centimetre scale, and a little generously, so the tackle reads at desktop size.
    var drawnLength: Double {
        switch self {
        case .fine: return 17
        case .jHook: return 23
        case .circle: return 30
        }
    }

    /// Line pressure (in units of a firm, safe pull) the hook holds before it straightens or the knot goes.
    var strength: Double {
        switch self {
        case .fine: return 0.62
        case .jHook: return 0.95
        case .circle: return 1.2
        }
    }

    /// How plainly a wary fish can see the metal.
    var visibility: Double {
        switch self {
        case .fine: return 0.12
        case .jHook: return 0.4
        // Big, but usually buried in the bait.
        case .circle: return 0.55
        }
    }

    var setsItself: Bool { self == .circle }
}

/// Natural baits hang under a float and can be picked off the hook; lures are fished without a
/// float and only work when they move like something alive.
enum Offering: String, CaseIterable, Codable, Identifiable, Sendable {
    case bloodworm, bread, pellet, dryFly, spinner, softWorm

    var id: String { rawValue }
    var isLure: Bool { self == .dryFly || self == .spinner || self == .softWorm }
    var usesFloat: Bool { !isLure }
    /// The dry fly rides the surface film.
    var floats: Bool { self == .dryFly }
    /// A spinner's blade only turns, and flashes, while it is pulled through the water.
    var needsMotion: Bool { self == .spinner }
    /// Something that sounds like feeding time when it plops in.
    var soundsLikeFood: Bool { self == .bread || self == .pellet }

    var title: String {
        switch self {
        case .bloodworm: return "Bloodworm"
        case .bread: return "Bread flake"
        case .pellet: return "Soaked pellet"
        case .dryFly: return "Dry fly"
        case .spinner: return "Micro spinner"
        case .softWorm: return "Soft worm jig"
        }
    }

    var detail: String {
        switch self {
        case .bloodworm: return "Every fish's favourite. Soft, so small fish pick it off fast."
        case .bread: return "Koi and gouramis love it. Slowly falls apart in the water."
        case .pellet: return "The food they know. Firm, and it plops like feeding time."
        case .dryFly: return "Floats on the film for rasboras, danios, bettas, and gouramis. Twitch it."
        case .spinner: return "Flash that makes a betta see red. Only works while you reel."
        case .softWorm: return "Sinks to the sand; hop it with a click. Bettas and barbs hit it, loaches nose at it."
        }
    }

    var symbol: String {
        switch self {
        case .bloodworm: return "scribble"
        case .bread: return "circle.hexagongrid"
        case .pellet: return "circle.fill"
        case .dryFly: return "ant"
        case .spinner: return "sparkle"
        case .softWorm: return "lasso"
        }
    }

    /// Sinking speed through still water, in centimetres per second (a 30 cm tank).
    var sinkCM: Double {
        switch self {
        // Baits fall at the pace of the split shot that cocks the float; lures carry their own lead.
        case .bloodworm: return 5.5
        case .bread: return 4.5
        case .pellet: return 5.5
        case .dryFly: return 0
        // The turning blade slows a spinner's fall to a flutter.
        case .spinner: return 4
        case .softWorm: return 10
        }
    }

    /// Share of the bait one full-sized peck removes.
    var peckLoss: Double {
        switch self {
        case .bloodworm: return 0.12
        case .bread: return 0.24
        case .pellet: return 0.3
        default: return 0
        }
    }
}

/// What each resident makes of the tackle. The numbers are tuned for play, but their shape
/// follows the fish: small-mouthed surface feeders, an aggressive betta, a cautious, bread-loving koi.
enum Tackle {
    /// How much a fish wants this offering, 0...1.
    static func appeal(_ species: FishSpecies, _ offering: Offering) -> Double {
        let table: [Offering: Double]
        switch species {
        case .rasbora: table = [.bloodworm: 0.85, .bread: 0.25, .pellet: 0.7, .dryFly: 0.75, .spinner: 0.12, .softWorm: 0.05]
        case .cherry: table = [.bloodworm: 0.9, .bread: 0.45, .pellet: 0.75, .dryFly: 0.4, .spinner: 0.35, .softWorm: 0.25]
        case .pearl: table = [.bloodworm: 0.6, .bread: 0.6, .pellet: 0.6, .dryFly: 0.7, .spinner: 0.05, .softWorm: 0.1]
        case .loach: table = [.bloodworm: 0.95, .bread: 0.2, .pellet: 0.65, .dryFly: 0, .spinner: 0, .softWorm: 0.4]
        // Celestial pearl danios keep to the lower water among plants and seldom rise.
        case .danio: table = [.bloodworm: 0.7, .bread: 0.1, .pellet: 0.55, .dryFly: 0.3, .spinner: 0.05, .softWorm: 0]
        case .golden: table = [.bloodworm: 0.9, .bread: 0.6, .pellet: 0.8, .dryFly: 0.45, .spinner: 0.35, .softWorm: 0.4]
        case .betta: table = [.bloodworm: 0.95, .bread: 0.1, .pellet: 0.6, .dryFly: 0.85, .spinner: 0.75, .softWorm: 0.5]
        case .koi: table = [.bloodworm: 0.6, .bread: 0.95, .pellet: 0.85, .dryFly: 0.2, .spinner: 0.15, .softWorm: 0.45]
        case .shrimp: table = [.bloodworm: 0.8, .bread: 0.6, .pellet: 0.9]
        // Thai micro crabs mostly filter and graze; a bait on the sand is an occasional treat.
        case .crab: table = [.bloodworm: 0.35, .bread: 0.2, .pellet: 0.3]
        }
        return table[offering] ?? 0
    }

    /// Chance a well-timed strike sets this hook in this mouth. A hook too big for the mouth
    /// mostly pulls free, which is how small fish strip big hooks.
    static func hookFit(_ species: FishSpecies, _ hook: HookKind) -> Double {
        switch (species, hook) {
        case (.danio, .fine): return 0.45
        case (.danio, .jHook): return 0.05
        case (.rasbora, .fine): return 0.75
        case (.rasbora, .jHook): return 0.2
        case (.cherry, .fine): return 0.8
        case (.cherry, .jHook): return 0.4
        case (.cherry, .circle): return 0.03
        case (.loach, .fine): return 0.7
        case (.loach, .jHook): return 0.3
        case (.loach, .circle): return 0.03
        case (.golden, .fine): return 0.78
        case (.golden, .jHook): return 0.55
        case (.golden, .circle): return 0.08
        case (.betta, .fine): return 0.75
        case (.betta, .jHook): return 0.5
        case (.betta, .circle): return 0.08
        case (.pearl, .fine): return 0.62
        case (.pearl, .jHook): return 0.8
        case (.pearl, .circle): return 0.3
        case (.koi, .fine): return 0.62
        case (.koi, .jHook): return 0.75
        case (.koi, .circle): return 0.9
        default: return 0
        }
    }

    /// How fast a hook loses bait to pecks: a big hook threads it on firmly, a tiny one barely.
    static func baitHold(_ hook: HookKind) -> Double {
        switch hook {
        case .fine: return 1.15
        case .jHook: return 1
        case .circle: return 0.5
        }
    }

    /// Wariness of anything odd about food: line, metal, movement.
    static func caution(_ species: FishSpecies) -> Double {
        switch species {
        case .koi: return 0.62
        case .pearl: return 0.55
        case .danio: return 0.6
        case .rasbora, .loach: return 0.4
        case .cherry: return 0.32
        case .golden: return 0.25
        case .betta: return 0.18
        case .shrimp, .crab: return 0.1
        }
    }

    /// Chance a fish following a lure, or watching it hop, turns and hits it.
    static func aggression(_ species: FishSpecies) -> Double {
        switch species {
        case .betta: return 0.8
        case .golden: return 0.4
        case .cherry: return 0.45
        case .koi: return 0.35
        case .loach: return 0.4
        case .rasbora, .danio: return 0.3
        case .pearl: return 0.2
        case .shrimp, .crab: return 0
        }
    }

    /// How hard a hooked fish pulls, relative to a firm, safe line pressure of 1.
    static func fightStrength(_ species: FishSpecies) -> Double {
        switch species {
        case .danio: return 0.14
        case .rasbora: return 0.2
        case .cherry: return 0.24
        case .betta: return 0.3
        case .loach: return 0.36
        case .golden: return 0.45
        case .pearl: return 0.55
        case .koi: return 1.05
        case .shrimp, .crab: return 0
        }
    }

    /// Seconds of hard fighting before the fish is spent.
    static func staminaSeconds(_ species: FishSpecies) -> Double {
        switch species {
        // A fish of a gram or two is simply lifted out; only the koi has the weight to take line for long.
        case .danio: return 1
        case .rasbora: return 1.2
        case .cherry: return 1.5
        case .betta: return 2
        case .loach: return 2.5
        case .golden: return 3.5
        case .pearl: return 6
        case .koi: return 17
        case .shrimp, .crab: return 1
        }
    }

    /// Head shakes and wriggles that loosen a hook on a slack line.
    static func shakiness(_ species: FishSpecies) -> Double {
        switch species {
        case .betta, .loach: return 1.45
        case .koi: return 1.2
        default: return 1
        }
    }

    /// How long a fish mouths a bait before it either swallows it or, far more often, spits it.
    static func holdTime(_ species: FishSpecies) -> ClosedRange<Double> {
        switch species {
        case .danio, .rasbora: return 0.6...0.9
        case .cherry: return 0.6...0.95
        case .betta: return 0.7...1.1
        case .golden, .loach: return 0.75...1.25
        case .pearl: return 0.95...1.55
        case .koi: return 1.2...2.1
        case .shrimp, .crab: return 1...1
        }
    }

    /// Bite size relative to a full peck.
    static func biteSize(_ species: FishSpecies) -> Double {
        switch species {
        case .danio: return 0.45
        case .rasbora: return 0.6
        case .cherry: return 0.7
        case .shrimp: return 0.3
        case .crab: return 0.45
        case .koi: return 1.6
        case .pearl: return 1.1
        default: return 0.9
        }
    }

    /// A typical adult in centimetres.
    static func typicalLengthCM(_ species: FishSpecies) -> Double {
        switch species {
        case .rasbora: return 4.5
        case .cherry: return 4.8
        case .pearl: return 10.5
        case .loach: return 8.5
        case .danio: return 2.1
        case .golden: return 7
        case .betta: return 6.2
        // A young koi (tosai) that fits the tank; drawn about three rasboras long.
        case .koi: return 15
        case .shrimp: return 2.5
        case .crab: return 1.2
        }
    }

    /// Each individual keeps one size, within about ±15% of its species' typical adult.
    static func lengthCM(_ species: FishSpecies, id: Int) -> Double {
        var dice = Dice(seed: 0x5172E ^ (UInt64(id) &* 0x9E3779B97F4A7C15))
        return (typicalLengthCM(species) * dice.normal(mean: 1, deviation: 0.08).clamped(to: 0.82...1.18) * 10).rounded() / 10
    }

    /// Something of about the same weight, for the catch card.
    static func comparison(grams: Double) -> String {
        switch grams {
        case ..<0.08: return "Lighter than a grain of rice."
        case ..<0.4: return "About the weight of a few grains of rice."
        case ..<1.5: return "About the weight of a paperclip."
        case ..<4: return "About the weight of a sugar cube."
        case ..<9: return "About the weight of a teaspoon of sugar."
        case ..<30: return "About the weight of an AA battery."
        case ..<70: return "About the weight of a golf ball."
        case ..<250: return "About the weight of an apple."
        case ..<700: return "About the weight of a can of soup."
        default: return "About the weight of a bag of sugar."
        }
    }

    /// A field note for each fish, shown in the catch log.
    static func hint(_ species: FishSpecies) -> String {
        switch species {
        case .rasbora: return "Fine hook, bloodworm or a dry fly"
        case .cherry: return "Fine hook, bloodworm or pellet in mid-water"
        case .pearl: return "J-hook, bread or a dry fly near the top"
        case .loach: return "Fine hook, bloodworm on the sand"
        case .danio: return "Fine hook, bloodworm low among the plants. Tiny mouths!"
        case .golden: return "Fine hook, pellet or bread; don't horse it"
        case .betta: return "Spinner or a dry fly; it hits hard"
        case .koi: return "Circle hook and bread. Let it run"
        case .shrimp, .crab: return "Bait thief"
        }
    }

    /// Weight from length, W = a·L³, with a body-shape factor: deep-bodied gouramis and koi
    /// weigh far more for their length than an eel-like loach.
    static func weightGrams(_ species: FishSpecies, lengthCM: Double) -> Double {
        let shape: Double
        switch species {
        case .koi: shape = 0.016
        case .pearl: shape = 0.014
        case .loach: shape = 0.003
        case .betta: shape = 0.011
        default: shape = 0.012
        }
        return shape * pow(lengthCM, 3)
    }
}

/// One fish landed.
struct CatchRecord: Codable, Equatable, Sendable {
    var species: FishSpecies
    var lengthCM: Double
    var weightGrams: Double
    var hook: HookKind
    var offering: Offering
    var fishID: Int
    /// This individual was caught before in this session; it is warier now.
    var caughtBefore = false
}

/// Everything worth telling the angler, in the order it happened.
enum FishingEvent: Equatable, Sendable {
    case cast
    case splash
    case spooked(FishSpecies)
    case curious(FishSpecies)
    case settled
    case interest(FishSpecies)
    case following(FishSpecies)
    case refused(FishSpecies)
    case nibble(FishSpecies)
    case baitStolen(FishSpecies)
    case take(FishSpecies)
    case struckEarly
    case twitch
    case missed(FishSpecies)
    case spat(FishSpecies)
    case hooked(FishSpecies)
    case run(FishSpecies)
    case surfaceThrash(FishSpecies)
    case threwHook(FishSpecies)
    case lineSnapped(FishSpecies)
    case hookStraightened(FishSpecies)
    case hookPulled(FishSpecies)
    case landed(CatchRecord)
    case released(FishSpecies)
    case crabClinging
    case crabLetGo
    case reeledIn
    case rigReady
}

enum RigPhase: String, Equatable, Sendable {
    /// Out of the water, ready to cast.
    case stowed
    /// Flying out to the spot that was clicked.
    case flying
    /// Sinking to its depth (or to the sand, for a lure).
    case sinking
    /// Fishing: hanging under the float, resting on the sand, or being retrieved.
    case fishing
    /// A fish is on.
    case fighting
    /// The fish is in the net and being admired before release.
    case landed
    /// Tying on a new hook after a break.
    case retying
}

/// The terminal tackle in the water, the float above it, and the state of the fight.
struct FishingRig {
    /// Reeling speed at the default reel, in scene widths per second (about 3 cm/s in the tank).
    static let reelSpeed = 0.042
    /// A lure being retrieved swims a little slower than the line comes in, as it rises and planes.
    static let retrieveSpeed = 0.034
    /// Seconds the catch is shown before it goes back.
    static let landedDuration = 3.2
    static let retieDuration = 2.4
    static let flightDuration = 0.75

    var hook: HookKind
    var offering: Offering
    var phase: RigPhase = .stowed
    /// The hook (and its bait), in scene coordinates.
    var x = 0.5, y = 0.8
    /// The rig hangs at mid-tank, where the lens focuses.
    var depth = 0.95
    /// Where the float rides on the surface, and how far it is pulled under (0 riding, 1 gone).
    var floatX = 0.5
    var floatDip = 0.0
    /// A brief bob from a peck or a twitch; decays.
    var floatBob = 0.0
    var bobClock = 0.0
    /// Height of the water surface above the rig, and the bait's set depth under the float.
    var surfaceY = 0.86
    var setDepthY = 0.5
    /// The rod tip, above the surface and off toward the angler.
    var rodTipX = 1.0, rodTipY = 1.1
    /// 1 = a fresh bait; it is picked off, dissolves, or is swallowed.
    var baitLeft = 1.0
    var flightTime = 0.0
    var flightFromX = 1.0
    var castX = 0.5
    var reeling = false
    var sinceTwitch = 99.0
    /// How fast the rig is moving through the water (scene widths per second).
    var speed = 0.0
    /// Seconds since the bait entered the water; its scent spreads.
    var soak = 0.0
    /// The fish mouthing the bait right now, and how long since it took it.
    var holderID: Int?
    var holdElapsed = 0.0
    var holdLimit = 0.0
    /// A strike asked for by the angler, applied in the next step.
    var pendingStrike = false
    /// Commotion every fish hears this step (the splash, a strike, a fish thrashing on the line),
    /// and commotion raised during this step, heard in the next.
    var disturbances: [Disturbance] = []
    var nextDisturbances: [Disturbance] = []
    /// Seconds since the rig hit the water, for the splash ring and its bubbles.
    var splashAge = 99.0
    /// Tackle chosen while a fish was on; tied on when the line next comes in.
    var pendingTackle: (hook: HookKind, offering: Offering)?
    var thrashClock = 0.0
    // The fight.
    var hookedID: Int?
    var lineLength = 0.3
    var pressure = 0.0
    var slackTime = 0.0
    var overload = 0.0
    var stamina = 1.0
    var running = false
    var runRemaining = 0.0
    var runAngle = 0.0
    var shakeClock = 0.0
    var fightTime = 0.0
    var timer = 0.0
    var landedCatch: CatchRecord?
    /// Fish this rig has already caught, so a second catch is noticed.
    var caughtIDs: Set<Int> = []
    var events: [FishingEvent] = []
    var dice: Dice
    /// Bread crumbs drifting off the hook.
    var crumbs: [Crumb] = []

    struct Crumb { var x: Double, y: Double, age: Double, size: Double, drift: Double }

    struct Disturbance {
        enum Kind { case splash, twitch, thrash }
        var kind: Kind
        var x: Double, y: Double
        var radius: Double
    }

    init(hook: HookKind, offering: Offering, seed: UInt64) {
        self.hook = hook
        self.offering = offering
        dice = Dice(seed: seed ^ 0xF15C)
    }

    var inWater: Bool { phase == .sinking || phase == .fishing || phase == .fighting }
    /// The rig can draw a fish's interest: in the water, baited or a lure, and nobody hooked.
    var isFishable: Bool { (phase == .sinking || phase == .fishing) && (offering.isLure || baitLeft > 0.04) }
    /// The float, for rigs that use one, is on the water.
    var showsFloat: Bool { offering.usesFloat && (inWater || phase == .landed) }
    /// A lure that is moving, or was just twitched, looks alive.
    var lureIsLively: Bool { speed > 0.008 || sinceTwitch < 1.6 }
    /// Room for the fish's mouth: a fish close to the rig counts as being at it.
    static let mouthReach = 0.014

    mutating func emit(_ event: FishingEvent) {
        events.append(event)
        // Nobody reading (a test, or a hidden window): keep only the recent story.
        if events.count > 96 { events.removeFirst(events.count - 64) }
    }

    /// Line length from the rod tip, in scene widths (a scene height is 1/aspect of a width).
    func lineDistance(_ x: Double, _ y: Double) -> Double { hypot(x - rodTipX, (y - rodTipY) / TankScale.aspect) }
}

enum AnglingPhase: String, Sendable {
    /// Hanging back a body length from the bait, looking it over.
    case inspecting
    /// Trailing a moving lure.
    case following
    /// Darting in for quick pecks that tear bits off the bait, backing off between them.
    case nibbling
    /// Going in to take the whole bait.
    case taking
    /// Bait in its mouth, turning away: the float slides under. Strike now.
    case holding
    case hooked
    /// In the net, out of the water.
    case landed
    /// Just put back: heading down and away.
    case released
    case fleeing
    case refusing
    /// A crab hanging on to the bait with its claws.
    case gripping
    /// A crab that let go of a lifted bait, falling back to the sand.
    case dropping

    /// Phases in which the fish swims purposefully at the bait, like a fish going for food.
    var isFocused: Bool { self == .inspecting || self == .nibbling || self == .taking || self == .following || self == .holding }
    /// Phases that count toward the crowd at the bait.
    var isAtBait: Bool { [.inspecting, .following, .nibbling, .taking, .holding, .gripping].contains(self) }
}

struct AnglingResponse {
    var phase: AnglingPhase
    var timer: Double
    var age = 0.0
    /// Where a fleeing, refusing, released, or bait-holding fish is heading.
    var x = 0.0, y = 0.0
    /// The side of the bait the fish came from (+1 right, -1 left).
    var side = 1.0
    var pecks = 0
    var maxPecks = 3
    var backOff = 0.0
    /// A gripping crab: how long it has been lifted, and how long it will hang on.
    var lifted = 0.0
    var grip = 0.0
    var announced = false
}

/// The persistent side of fishing: chosen tackle and a lifetime catch log.
struct AnglingLog: Codable, Equatable, Sendable {
    struct Tally: Codable, Equatable, Sendable {
        var count = 0
        var bestCM = 0.0
        var bestGrams = 0.0
        var bestOn: Offering?
    }

    var hook: HookKind = .fine
    var offering: Offering = .bloodworm
    var casts = 0
    var bites = 0
    var hooked = 0
    var landed = 0
    var lost = 0
    var baitsStolen = 0
    var tallies: [String: Tally] = [:]
    /// Soft sound cues in the fishing window (nil: on).
    var sounds: Bool? = nil

    func tally(_ species: FishSpecies) -> Tally { tallies[species.rawValue] ?? Tally() }
    var speciesCaught: Int { tallies.values.filter { $0.count > 0 }.count }

    /// Updates the log. Returns true for a new personal best of that species.
    @discardableResult mutating func record(_ event: FishingEvent) -> Bool {
        switch event {
        case .cast: casts += 1
        case .take: bites += 1
        case .hooked: hooked += 1
        case .threwHook, .lineSnapped, .hookStraightened, .hookPulled: lost += 1
        case .baitStolen: baitsStolen += 1
        case .landed(let record):
            landed += 1
            var t = tally(record.species)
            t.count += 1
            let best = record.lengthCM > t.bestCM
            if best { t.bestCM = record.lengthCM; t.bestGrams = record.weightGrams; t.bestOn = record.offering }
            tallies[record.species.rawValue] = t
            return best && t.count > 1
        default: break
        }
        return false
    }
}
