import Foundation

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

// Shares the fish's depth axis: larger values are closer to the viewer.
enum ParticlePerspective {
    static func scale(_ depth: Double) -> Double { pow(depth, 1.45) }
    static func layer(_ depth: Double) -> Double { 5 + depth }
    /// Out-of-focus blur in points: the lens focuses on the middle of the tank, so the
    /// nearest and farthest particles soften.
    static func blur(_ depth: Double) -> Double { abs(depth - 0.95) * 2.6 }
    static func distance(band: Int, fraction: Double) -> Double {
        [0.55, 0.87, 1.24][band % 3] + fraction * 0.15
    }
}

struct AquariumSimulation {
    // MARK: Tuning

    /// Longest simulated step; a wake from sleep must not teleport fish.
    static let maximumStep = 1.0 / 15.0
    static let pelletsPerFeeding = 12
    static let maximumPellets = 36
    static let pelletLifetime = 70.0
    /// Pellets come to rest on the sand at this height.
    static let sandHeight = 0.082
    /// Vertical distances count less than horizontal ones when fish judge nearness.
    static let verticalWeight = 0.65
    static let mouthReach = 0.016
    /// Longest a fish spends settling back after a meal before it wanders again.
    static let leavingTimeout = 8.0
    /// A fish only swaps the side it faces when its horizontal intent exceeds this share of cruise speed...
    static let facingThreshold = 0.25
    /// ...for this long (movement units; about 1.1 s at the default speed), or briefly when food is involved.
    static let reversalPatience = 0.55
    static let feedingReversalPatience = 0.12
    /// A turn at least this large banks toward whichever depth direction has room.
    static let bankingAngle = 2.0
    /// Within this much movement after a large turn (about four seconds at the default
    /// speed), the next one unwinds the other way, so reversals never chain into a pinwheel.
    static let unwindWindow = 2.0
    /// Share of forward speed kept while the body still points away from the goal: wandering
    /// fish sweep a wide arc, while a fish that spots food pivots toward it without drifting away.
    static let wanderingGlide = 0.45
    static let feedingGlide = 0.0
    /// How strongly forward travel during a turn carries a fish nearer or farther.
    static let depthTravel = 6.0
    static let turnGain = 3.5
    /// How quickly turning speed follows its target (per movement unit).
    static let turnResponse = 16.0
    static let feedingTurnLimit = 4.4
    /// Radians per movement unit squared; turns ease in and out instead of snapping.
    static let maximumTurnAcceleration = 60.0
    /// How much faster loaches and shrimp turn while facing toward or away from the viewer.
    static let headOnHurry = 1.6
    /// Turn rate still allowed when a fish has almost no forward speed (radians per movement unit).
    static let stationaryTurnRate = 0.6
    /// Turning speed of a gourami or betta rotating in place on its pectoral fins.
    static let hoverTurnRate = 1.6
    /// Shrimp flee from a fish that hunts them when it comes this close.
    static let threatDistance = 0.06
    /// Leg-cycle radians per movement unit when a crab walks at cruise speed.
    static let crabStepsPerCruise = 2.2
    /// Leg-cycle radians per movement unit for a walking shrimp.
    static let shrimpStepRate = 18.0
    /// Bed residents closer than this in depth keep apart; farther apart they simply pass in front.
    static let bedLayer = 0.12
    /// How quickly touching bed residents slide apart, as a multiple of cruise speed.
    static let bedNudge = 1.5
    /// How far above its usual band a fleeing shrimp may rise, in scene heights.
    static let escapeHeadroom = 0.07
    /// Each tail flip carries a shrimp about one and a half body lengths.
    static let flipDistance = 1.8

    // MARK: State

    private(set) var fish: [FishState] = []
    private(set) var food: [FoodPellet] = []
    private(set) var pendingFood: [FoodPellet] = []
    private(set) var bubbleField: BubbleField
    private(set) var sand: SandField
    var bubbles: [BubbleState] { bubbleField.bubbles }
    private(set) var mealsEaten = 0
    private(set) var time = 0.0
    var visibleRegion = SwimRegion(left: 0, right: 1, bottom: 0, top: 1)

    private let entitySeed: UInt64
    private var dice: Dice
    private var nextID = 0
    private var nextFoodID = 0
    private var bubbleRegion: SwimRegion?
    private var lastDropX: Double?
    private var theme: AquariumTheme?
    private var neighbors: [Neighbor] = []

    private struct Neighbor {
        var id: Int, species: FishSpecies
        var x: Double, y: Double, vx: Double, vy: Double
        var size: Double
        var depth: Double
    }

    /// Where a fish wants to go this frame and how urgently.
    private struct SteeringGoal {
        var x: Double, y: Double
        var region: SwimRegion
        var targetFood: Int?
    }

    init(seed: UInt64 = 42017) {
        dice = Dice(seed: seed)
        entitySeed = seed
        bubbleField = BubbleField(seed: seed ^ 0xBABB1E)
        sand = SandField(seed: seed ^ 0x5A4D)
    }

    static func angleDifference(_ target: Double, _ current: Double) -> Double {
        atan2(sin(target - current), cos(target - current))
    }

    // MARK: Regions

    static func region(for species: FishSpecies, theme: AquariumTheme) -> SwimRegion {
        if species.isBottomDweller {
            var bed: SwimRegion
            switch theme {
            case .grove: bed = SwimRegion(left: 0.47, right: 0.90, bottom: 0.06, top: 0.115)
            case .river: bed = SwimRegion(left: 0.14, right: 0.63, bottom: 0.06, top: 0.13)
            case .spring: bed = SwimRegion(left: 0.21, right: 0.60, bottom: 0.06, top: 0.12)
            }
            if species == .shrimp { bed.top += 0.08 }
            return bed
        }
        let x: (left: Double, right: Double)
        switch theme {
        case .grove: x = (0.43, 0.89)
        case .river: x = (0.19, 0.77)
        case .spring: x = (0.09, 0.61)
        }
        switch species {
        case .pearl, .betta: return SwimRegion(left: x.left, right: x.right, bottom: 0.53, top: 0.84)
        case .koi: return SwimRegion(left: x.left + 0.025, right: x.right - 0.025, bottom: 0.32, top: 0.66)
        case .cherry: return SwimRegion(left: x.left, right: x.right, bottom: 0.27, top: 0.57)
        default: return SwimRegion(left: x.left, right: x.right, bottom: 0.39, top: 0.77)
        }
    }

    private func swimmingRegion(for fish: FishState, theme: AquariumTheme) -> SwimRegion {
        var r = Self.region(for: fish.species, theme: theme)
        // Hungry swimmers may leave their usual band to reach food near the surface or sand.
        if fish.feeding != nil && !fish.species.isBottomDweller {
            r.bottom = min(r.bottom, 0.20)
            r.top = max(r.top, 0.85)
        }
        if fish.species == .shrimp {
            // A tail flip carries a shrimp up into open water; afterwards it sinks back down
            // rather than snapping to its usual band.
            if fish.shrimpBehavior.isEscaping { r.top += Self.escapeHeadroom }
            r.top = max(r.top, fish.y)
        }
        return r.intersecting(visibleRegion)
    }

    // MARK: Population

    mutating func synchronize(_ configuration: AquariumConfiguration) {
        if theme != configuration.theme {
            food.removeAll(); pendingFood.removeAll(); lastDropX = nil
            bubbleRegion = nil
            theme = configuration.theme
            for i in fish.indices {
                fish[i].feeding = nil
                // A fresh stream, distinct from the one the shrimp was born with.
                fish[i].shrimpBehavior = ShrimpBehavior(seed: entitySeed ^ (UInt64(fish[i].id) &* 0x9E3779B97F4A7C15) ^ 0x5A11 ^ 0x7E3E)
            }
        }
        placeBubbleSources(theme: configuration.theme)
        for species in FishSpecies.allCases {
            let desired = configuration.count(species)
            let currentIDs = fish.filter { $0.species == species }.map(\.id)
            let remove = Set(currentIDs.dropFirst(desired))
            fish.removeAll { remove.contains($0.id) }
            let region = Self.region(for: species, theme: configuration.theme).intersecting(visibleRegion)
            for _ in 0..<max(0, desired - currentIDs.count) { fish.append(makeFish(species, in: region)) }
        }
        for i in fish.indices {
            let r = swimmingRegion(for: fish[i], theme: configuration.theme)
            (fish[i].x, fish[i].y) = r.constrain(x: fish[i].x, y: fish[i].y)
        }
    }

    /// Crabs keep to the nearer part of the bed and loaches to the farther part, so the two
    /// pass in front of each other rather than piling up on one line.
    static func birthDepths(for species: FishSpecies) -> ClosedRange<Double> {
        switch species {
        case .crab: return 0.98...FishState.depthRange.upperBound
        case .loach: return FishState.depthRange.lowerBound...0.86
        default: return FishState.depthRange
        }
    }

    /// Every individual owns independent random streams derived from its identity.
    private mutating func makeFish(_ species: FishSpecies, in region: SwimRegion) -> FishState {
        let personalSeed = entitySeed ^ (UInt64(nextID) &* 0x9E3779B97F4A7C15)
        var birth = Dice(seed: personalSeed ^ 0xB17A)
        let facingRight = birth.chance(0.5)
        var resident = FishState(id: nextID, species: species,
            x: birth.value(region.left...region.right), y: birth.value(region.bottom...region.top),
            depth: birth.value(Self.birthDepths(for: species)), facingRight: facingRight,
            finPhase: birth.value(0...6), moodRemaining: birth.value(1...10))
        resident.personality = Personality(dice: &birth)
        resident.stroke = FishStroke(seed: personalSeed ^ 0xF1A5)
        resident.navigation = FishNavigation(seed: personalSeed ^ 0xA11CE, heading: facingRight ? 0 : .pi,
                                             personality: resident.personality, flatness: species.isBottomDweller ? 0.35 : 1)
        resident.dice = Dice(seed: personalSeed ^ 0xBEA710)
        resident.shrimpBehavior = ShrimpBehavior(seed: personalSeed ^ 0x5A11)
        resident.crabGait = CrabGait(seed: personalSeed ^ 0xC2AB)
        nextID += 1
        return resident
    }

    // MARK: Bubbles and sand

    /// Sources follow the theme and stay inside the visible part of a cropped display.
    private mutating func placeBubbleSources(theme: AquariumTheme) {
        let region = visibleRegion
        if let placed = bubbleRegion, placed.left == region.left, placed.right == region.right, placed.top == region.top { return }
        bubbleField.place(theme: theme, visible: region)
        bubbleRegion = region
    }

    /// Where a resident's body meets the sand, in scene coordinates.
    private static func sandContact(of f: FishState) -> Double {
        f.y - f.species.bodySize * f.depth * (f.species.isInvertebrate ? 0.25 : 0.085) / 900
    }

    // MARK: Feeding

    mutating func feed(_ configuration: AquariumConfiguration) {
        guard configuration.mode == .live, configuration.swimmingSpeed > 0, !fish.isEmpty else { return }
        let swimmers = fish.filter { !$0.species.isBottomDweller }
        let residents = swimmers.isEmpty ? fish : swimmers
        let r = Self.region(for: swimmers.isEmpty ? .loach : .rasbora, theme: configuration.theme).intersecting(visibleRegion)
        let sources = sprinkleSources(in: r, near: residents)
        let count = min(Self.pelletsPerFeeding, max(0, Self.maximumPellets - food.count - pendingFood.count))
        // Bottom dwellers are fed just above the sand so the food reaches them quickly.
        let dropY = swimmers.isEmpty ? min(visibleRegion.top, r.top + 0.075) : visibleRegion.top
        for i in 0..<count {
            let batch = i / 4
            var pelletDice = Dice(seed: entitySeed ^ (UInt64(nextFoodID) &* 0x9E3779B97F4A7C15) ^ 0xF00D)
            var pellet = FoodPellet(id: nextFoodID,
                x: min(r.right, max(r.left, sources[batch] + pelletDice.value(-0.018...0.018))),
                y: max(r.bottom, dropY - pelletDice.value(0...0.016)))
            pellet.releaseDelay = i == 0 ? 0 : Double(batch) * 0.42 + pelletDice.value(0.06...0.28)
            // Slow-sinking micro-pellets fall nearly straight at about 1 to 1.5 cm/s.
            pellet.sinkSpeed = TankScale.height(cm: pelletDice.value(0.9...1.5))
            pellet.drift = pelletDice.value(0.0003...0.001)
            pellet.phase = pelletDice.value(0...(2 * .pi))
            pellet.size = pelletDice.value(0.65...1.15)
            pellet.rotation = pelletDice.value(-.pi ... .pi)
            pellet.spin = pelletDice.value(-1.4...1.4)
            pellet.floatDuration = pelletDice.value(0.12...0.60)
            pellet.depth = ParticlePerspective.distance(band: nextFoodID, fraction: pelletDice.next())
            pellet.tumble = pelletDice.value(-.pi ... .pi)
            pellet.tumbleSpeed = pelletDice.value(0.35...0.85)
            if pellet.releaseDelay == 0 { food.append(pellet) } else { pendingFood.append(pellet) }
            nextFoodID += 1
        }
    }

    /// Three sprinkle positions, spread apart and away from the previous feeding.
    private mutating func sprinkleSources(in r: SwimRegion, near residents: [FishState]) -> [Double] {
        let width = max(0.001, r.width)
        var sources: [Double] = []
        for batch in 0..<3 {
            var candidate = dice.value(r.left...r.right)
            if let last = sources.last ?? lastDropX, abs(candidate - last) < width * 0.20 {
                candidate = r.left + (candidate - r.left + width * 0.45).truncatingRemainder(dividingBy: width)
            }
            // Keep the first sprinkle close enough for an immediate, visible reaction.
            if batch == 0, let nearby = residents.min(by: { abs($0.x - candidate) < abs($1.x - candidate) }) {
                candidate = candidate * 0.7 + nearby.x * 0.3
            }
            sources.append(min(r.right, max(r.left, candidate)))
        }
        lastDropX = sources.last
        return sources
    }

    private mutating func advanceFood(_ dt: Double) {
        for i in pendingFood.indices { pendingFood[i].releaseDelay -= dt }
        food.append(contentsOf: pendingFood.filter { $0.releaseDelay <= 0 })
        pendingFood.removeAll { $0.releaseDelay <= 0 }
        for i in food.indices {
            food[i].age += dt
            let sinking = min(1, max(0, (food[i].age - food[i].floatDuration) * 2.0))
            food[i].y = max(Self.sandHeight, food[i].y - dt * food[i].sinkSpeed * sinking)
            food[i].x += sin(food[i].age * 0.8 + food[i].phase) * dt * food[i].drift
            // Pellets stop tumbling as they settle on the sand.
            let settling = min(1, max(0, (food[i].y - Self.sandHeight) / 0.025))
            food[i].rotation += food[i].spin * dt * settling
            food[i].tumble += food[i].tumbleSpeed * dt * settling
        }
        food.removeAll { $0.age > Self.pelletLifetime || $0.x < visibleRegion.left || $0.x > visibleRegion.right }
    }

    // MARK: Simulation step

    mutating func step(delta: Double, configuration: AquariumConfiguration) {
        guard configuration.mode == .live, delta.isFinite, delta > 0 else { return }
        let dt = min(delta, Self.maximumStep)
        time += dt
        if configuration.bubbles {
            if let theme { placeBubbleSources(theme: theme) }
            bubbleField.advance(dt, visible: visibleRegion)
        }
        sand.advance(dt)
        guard configuration.swimmingSpeed > 0 else { return }
        let movement = dt * configuration.swimmingSpeed
        advanceFood(dt)
        neighbors = fish.map { Neighbor(id: $0.id, species: $0.species, x: $0.x, y: $0.y, vx: $0.vx, vy: $0.vy,
                                        size: $0.species.bodySize * $0.depth, depth: $0.depth) }
        // How many fish currently chase each pellet. Maintained incrementally, so choosing
        // food stays linear in the number of fish instead of rescanning the school per pellet.
        var claims: [Int: Int] = [:]
        for f in fish { if let target = f.feeding?.targetID { claims[target, default: 0] += 1 } }
        for i in fish.indices {
            var f = fish[i]
            let previousTarget = f.feeding?.targetID
            advance(&f, dt: dt, movement: movement, theme: configuration.theme, claims: claims)
            let newTarget = f.feeding?.targetID
            if previousTarget != newTarget {
                if let previousTarget {
                    assert((claims[previousTarget] ?? 0) > 0, "Pellet claim counts out of sync")
                    claims[previousTarget, default: 0] -= 1
                }
                if let newTarget { claims[newTarget, default: 0] += 1 }
            }
            fish[i] = f
        }
    }

    private mutating func advance(_ f: inout FishState, dt: Double, movement: Double, theme: AquariumTheme, claims: [Int: Int]) {
        let home = Self.region(for: f.species, theme: theme).intersecting(visibleRegion)
        f.feedingCooldown = max(0, f.feedingCooldown - dt)
        f.moodRemaining -= movement
        f.appetite = min(1, f.appetite + movement * 0.025)
        chooseMood(&f)
        if f.feeding == nil {
            f.navigation.advance(delta: movement, x: f.x, y: f.y, region: home, resting: f.mood == .hover)
            noticeFood(&f, home: home, claims: claims)
        }
        var goal = steeringGoal(&f, dt: dt, home: home, theme: theme)
        let previousBouts = f.crabGait.bouts, wasStepping = f.shrimpBehavior.stepping
        if f.species == .shrimp { steerShrimp(&f, goal: &goal, movement: movement, home: home) }
        if f.species == .crab {
            f.crabGait.advance(delta: movement, x: f.x, y: f.y, region: home)
            if f.crabGait.walking && isBlockedOnBed(f) { f.crabGait.bumped() }
            // Away from food, the gait alone decides where a crab walks.
            if f.feeding == nil { goal.x = f.x; goal.y = f.y }
        }
        let desiredActivity = activityTarget(for: f)
        // Shrimp legs start and stop within a step; fish ease between moods.
        let activityRate = f.species == .shrimp && f.feeding == nil ? 12.0 : 3.5
        f.activity += (desiredActivity - f.activity) * (1 - exp(-movement * activityRate))
        let (dx, dy) = steeringVector(for: f, towards: goal)
        swim(&f, dx: dx, dy: dy, goal: goal, movement: movement)
        if f.species.isBottomDweller { nudgeApartOnBed(&f, region: goal.region, movement: movement) }
        eatIfReached(&f, targetFood: goal.targetFood)
        stirSand(f, previousBouts: previousBouts, wasStepping: wasStepping, movement: movement)
    }

    /// Residents that work the bed kick up a little sand as they go.
    private mutating func stirSand(_ f: FishState, previousBouts: Int, wasStepping: Bool, movement: Double) {
        let floor = Self.sandContact(of: f)
        switch f.species {
        case .loach:
            // A foraging loach pauses to nose into the sand, throwing up a puff each time.
            let sifting = f.feeding == nil && f.mood == .forage && f.forwardSpeed < f.species.cruiseSpeed * 0.3
            if sifting && sand.chance(movement * 2) {
                let snout = f.x + cos(f.yaw) * f.species.bodyLength * 0.45
                sand.puff(x: snout, floor: floor, depth: f.depth, strength: 0.6)
            }
        case .crab:
            if f.crabGait.bouts != previousBouts { sand.puff(x: f.x, floor: floor, depth: f.depth, strength: 0.35) }
        case .shrimp:
            let picking = f.shrimpBehavior.phase == .grazing && f.shrimpBehavior.stepping && !wasStepping
            if picking && sand.chance(0.35) { sand.puff(x: f.x, floor: floor, depth: f.depth, strength: 0.3) }
        default:
            break
        }
    }

    /// Moods change at irregular intervals; slow gliders and invertebrates rest more often.
    private func chooseMood(_ f: inout FishState) {
        guard f.moodRemaining <= 0 || (f.mood == .feeding && food.isEmpty) else { return }
        let roll = f.dice.next()
        let restChance = f.species.isSlowGlider || f.species.isInvertebrate ? 0.43 : 0.25
        // Mood lengths are random waits: mostly short, occasionally long.
        if roll < restChance {
            f.mood = .hover
            f.moodRemaining = f.dice.exponential(mean: 3).clamped(to: 1...9)
        } else if roll > 0.92 && !f.species.isInvertebrate {
            f.mood = .dash
            f.moodRemaining = f.dice.value(0.65...1.2)
        } else {
            f.mood = f.species.isBottomDweller ? .forage : .cruise
            f.moodRemaining = f.dice.exponential(mean: 8).clamped(to: 3...20)
        }
    }

    /// A hungry fish picks the nearest pellet in view, preferring ones fewer others are chasing.
    private func noticeFood(_ f: inout FishState, home: SwimRegion, claims: [Int: Int]) {
        guard f.feedingCooldown <= 0 && f.appetite > 0.35 else { return }
        let awareness = f.species.isBottomDweller ? 0.13 : 0.36
        let lowestReach = f.species.isBottomDweller ? home.bottom : 0.20
        var closest: FoodPellet?
        var bestScore = Double.infinity
        for pellet in food where pellet.x >= home.left && pellet.x <= home.right && pellet.y >= lowestReach {
            let distance = hypot(pellet.x - f.x, (pellet.y - f.y) * 0.55)
            guard distance < awareness else { continue }
            let score = distance + Double(claims[pellet.id] ?? 0) * 0.045
            if score < bestScore { bestScore = score; closest = pellet }
        }
        guard let pellet = closest else { return }
        let reaction = f.dice.value(0.15...0.95) + hypot(pellet.x - f.x, (pellet.y - f.y) * 0.55) * 1.5
        f.feeding = FeedingResponse(targetID: pellet.id, x: pellet.x, y: pellet.y, remaining: reaction)
    }

    /// The point a fish swims toward: its wandering heading, or a pellet while feeding.
    private func steeringGoal(_ f: inout FishState, dt: Double, home: SwimRegion, theme: AquariumTheme) -> SteeringGoal {
        let lookAhead = 0.075
        var r = swimmingRegion(for: f, theme: theme)
        let (wanderX, wanderY) = r.constrain(x: f.x + cos(f.navigation.heading) * lookAhead,
                                             y: f.y + sin(f.navigation.heading) * lookAhead / Self.verticalWeight)
        guard var response = f.feeding else { return SteeringGoal(x: wanderX, y: wanderY, region: r) }
        response.age += dt
        response.remaining -= dt
        var beginLeaving = false
        if response.phase == .noticing || response.phase == .approaching {
            if let pellet = food.first(where: { $0.id == response.targetID }),
               pellet.y >= r.bottom - 0.015, pellet.x >= r.left, pellet.x <= r.right {
                response.x = pellet.x
                response.y = pellet.y
                if response.remaining <= 0 && response.phase == .noticing {
                    response.phase = .approaching
                    response.age = 0
                }
            } else {
                response.phase = .leaving
                beginLeaving = true
            }
        }
        if response.phase == .nibbling && response.remaining <= 0 {
            response.phase = .leaving
            beginLeaving = true
        }
        if beginLeaving {
            // Scatter gently to individual resting spots before joining the group again.
            let drop = f.dice.value(f.species.isBottomDweller ? 0.004...0.012 : 0.045...0.10)
            (response.x, response.y) = home.constrain(x: f.x + f.dice.value(-0.09...0.09), y: f.y - drop)
            let inset = home.height * 0.12
            response.y = min(home.top - inset, max(home.bottom + inset, response.y))
            response.remaining = f.dice.value(2.5...4.5)
            response.age = 0
        }
        f.feeding = response
        r = swimmingRegion(for: f, theme: theme)
        switch response.phase {
        case .noticing:
            return SteeringGoal(x: wanderX, y: wanderY, region: r)
        case .approaching:
            f.mood = .feeding
            f.moodRemaining = 1
            return SteeringGoal(x: response.x, y: min(r.top, max(r.bottom, response.y)), region: r, targetFood: response.targetID)
        case .nibbling:
            f.mood = .feeding
            f.moodRemaining = 1
            return SteeringGoal(x: f.x, y: f.y, region: r)
        case .leaving:
            f.mood = .cruise
            f.moodRemaining = 3
            let arrived = hypot(response.x - f.x, (response.y - f.y) * Self.verticalWeight) < 0.025
                && f.y >= home.bottom && f.y <= home.top
            // After a while a fish simply carries on from wherever it is; its usual band pulls it back.
            if response.age > 2 && arrived || response.age > Self.leavingTimeout {
                f.feeding = nil
                f.feedingCooldown = f.dice.value(6...10)
                f.mood = .hover
                f.moodRemaining = f.dice.value(2...4)
            }
            return SteeringGoal(x: response.x, y: response.y, region: r)
        }
    }

    private func steerShrimp(_ f: inout FishState, goal: inout SteeringGoal, movement: Double, home: SwimRegion) {
        if let threat = nearestThreat(to: f) {
            _ = f.shrimpBehavior.startle(threatDirection: threat.x >= f.x ? 1 : -1, room: (f.x - home.left, home.right - f.x))
        }
        f.shrimpBehavior.advance(delta: movement, x: f.x, y: f.y, region: home, feeding: f.feeding != nil)
        guard f.feeding == nil else { return }
        switch f.shrimpBehavior.phase {
        case .grazing: goal.y = min(goal.y, ShrimpBehavior.bedTop(of: home))
        case .drifting, .seekingCover: goal.x = f.shrimpBehavior.target.x; goal.y = f.shrimpBehavior.target.y
        case .hidden, .emerging: goal.x = f.x; goal.y = f.y
        }
    }

    /// The sand floor recedes away from the glass, so a resident farther back on the bed is drawn
    /// a little higher on screen (a share of the artwork's height).
    static func bedLift(_ depth: Double) -> Double { (1.0 - depth) * 0.07 }

    /// Vertical separation of two bed residents as they appear on screen, including the lift.
    static func bedGap(_ y: Double, _ depth: Double, _ otherY: Double, _ otherDepth: Double) -> Double {
        (y + bedLift(depth)) - (otherY + bedLift(otherDepth))
    }

    /// A crab and another bed resident: crabs never settle over a loach or shrimp, at any depth,
    /// because their splayed legs would seem to stand on it.
    static func crabAndLoach(_ a: FishSpecies, _ b: FishSpecies) -> Bool {
        a == .crab || b == .crab
    }

    /// How far apart two bed residents must be up and down the screen: a crab's legs reach well
    /// above and below its shell.
    static func bedReachY(_ a: FishSpecies, _ b: FishSpecies) -> Double {
        crabAndLoach(a, b) ? 0.035 : 0.02
    }

    /// A walking crab has another bed resident right ahead of it at the same depth.
    private func isBlockedOnBed(_ f: FishState) -> Bool {
        let heading = cos(f.crabGait.direction)
        return neighbors.contains { other in
            guard other.id != f.id, other.species.isBottomDweller,
                  abs(other.depth - f.depth) < Self.bedLayer || Self.crabAndLoach(f.species, other.species),
                  abs(Self.bedGap(f.y, f.depth, other.y, other.depth)) < 0.015 else { return false }
            let reach = (f.species.bedFootprint * f.depth + other.species.bedFootprint * other.depth) * 0.5
            let ahead = (other.x - f.x) * heading
            return ahead > 0 && ahead < reach
        }
    }

    /// Residents lying on the bed that touch at the same depth slide gently apart along the sand,
    /// whichever way they face, as bodies bump and settle side by side.
    private func nudgeApartOnBed(_ f: inout FishState, region: SwimRegion, movement: Double) {
        var push = 0.0
        for other in neighbors where other.id != f.id && other.species.isBottomDweller
            && (abs(other.depth - f.depth) < Self.bedLayer || Self.crabAndLoach(f.species, other.species)) {
            let reachX = (f.species.bedFootprint * f.depth + other.species.bedFootprint * other.depth) * 0.5 * 0.9
            let sx = f.x - other.x, sy = Self.bedGap(f.y, f.depth, other.y, other.depth)
            let gap = hypot(sx / reachX, sy / Self.bedReachY(f.species, other.species))
            guard gap < 1 else { continue }
            let side: Double = sx != 0 ? (sx > 0 ? 1 : -1) : (f.id < other.id ? -1 : 1)
            push += side * (1 - gap)
        }
        guard push != 0 else { return }
        f.x += push.clamped(to: -1...1) * f.species.cruiseSpeed * Self.bedNudge * movement
        (f.x, f.y) = region.constrain(x: f.x, y: f.y)
    }

    /// The closest fish that hunts shrimp, if one is within striking distance.
    private func nearestThreat(to f: FishState) -> Neighbor? {
        neighbors
            .map { ($0, hypot($0.x - f.x, ($0.y - f.y) * Self.verticalWeight)) }
            .filter { $0.0.species.huntsShrimp && $0.1 < Self.threatDistance }
            .min { $0.1 < $1.1 }?.0
    }

    /// How energetically a fish swims, relative to its cruise speed.
    private func activityTarget(for f: FishState) -> Double {
        if f.species == .shrimp && f.feeding == nil { return f.shrimpBehavior.activity }
        if f.feeding?.phase == .nibbling { return 0.18 }
        if f.feeding?.phase == .leaving { return 0.7 }
        switch f.mood {
        case .hover: return 0.035
        case .dash: return 2.5
        case .forage: return 0.42
        case .cruise: return 0.85
        case .feeding:
            let eagerness = f.species.isInvertebrate ? 1.25 : (f.species.isSlowGlider ? 1.8 : 2.7)
            return eagerness * (0.92 + f.depth * 0.13)
        }
    }

    /// Direction to the goal, plus personal space and loose schooling with the same species.
    private func steeringVector(for f: FishState, towards goal: SteeringGoal) -> (Double, Double) {
        var dx = goal.x - f.x, dy = (goal.y - f.y) * Self.verticalWeight
        if f.species.isBottomDweller && !f.isChasingFood {
            // On the bed, a distant goal only sets the direction; close neighbours then get the room they need.
            let reach = hypot(dx, dy)
            if reach > 0.025 { dx *= 0.025 / reach; dy *= 0.025 / reach }
        }
        var shoalX = 0.0, shoalY = 0.0, shoalVX = 0.0, shoalVY = 0.0, shoalCount = 0.0
        let schooling = f.species.isSchooling && f.feeding == nil
        for other in neighbors where other.id != f.id {
            let sx = f.x - other.x, sy = (f.y - other.y) * Self.verticalWeight
            let squaredDistance = sx * sx + sy * sy
            if schooling && other.species == f.species && squaredDistance < 0.0225 {
                shoalX -= sx; shoalY -= sy
                shoalVX += other.vx; shoalVY += other.vy
                shoalCount += 1
            }
            if f.species.isBottomDweller && other.species.isBottomDweller {
                // Residents lying on the shallow bed make room by their actual lengths, side by
                // side along the sand, instead of piling on top of one another.
                // Animals at clearly different depths may pass in front of one another, except
                // that a crab never settles right over a loach, where it would seem to stand on it.
                guard abs(other.depth - f.depth) < Self.bedLayer || Self.crabAndLoach(f.species, other.species) else { continue }
                let reachX = (f.species.bedFootprint * f.depth + other.species.bedFootprint * other.depth) * 0.5 * 0.9
                let reachY = Self.bedReachY(f.species, other.species)
                let bedY = Self.bedGap(f.y, f.depth, other.y, other.depth)
                let gap = hypot(sx / reachX, bedY / reachY)
                if gap < 1 {
                    // While feeding they crowd in, but never lie right on top of one another.
                    let feedingPush = Self.crabAndLoach(f.species, other.species) ? 0.3
                        : (f.species == .loach && other.species == .loach ? 0.12 : (gap < 0.6 ? 0.08 : 0.025))
                    let force = (1 - gap) * (f.feeding == nil ? 0.3 : feedingPush)
                    let side: Double = sx != 0 ? (sx > 0 ? 1 : -1) : (f.id < other.id ? -1 : 1)
                    dx += side * force
                    if gap > 1e-6 { dy += sy / (gap * reachY) * force * 0.15 }
                }
                continue
            }
            let spacing = (f.species.bodySize * f.depth + other.size) / 3200 * 0.62
            if squaredDistance > 1e-10 && squaredDistance < spacing * spacing {
                let distance = sqrt(squaredDistance)
                let force = (1 - distance / spacing) * (f.feeding == nil ? 0.11 : 0.035)
                dx += sx / distance * force
                dy += sy / distance * force
            }
        }
        if shoalCount > 0 {
            let affinity = f.navigation.shoalAffinity / shoalCount
            dx += (shoalX + shoalVX * 0.35) * affinity
            dy += (shoalY + shoalVY * 0.35) * affinity
        }
        return (dx, dy)
    }

    private func swim(_ f: inout FishState, dx: Double, dy: Double, goal: SteeringGoal, movement: Double) {
        let distance = max(0.001, hypot(dx, dy))
        let pace = (f.feeding == nil ? f.navigation.speedFactor : 1) * f.personality.boldness
        let speed = f.species.cruiseSpeed * f.activity * pace * min(1, distance / 0.025)
        var desiredVX = dx / distance * speed, desiredVY = dy / distance * speed
        let previousSpeed = hypot(f.vx, f.vy)
        let previousYaw = f.yaw, previousYawVelocity = f.yawVelocity
        var responseRate = goal.targetFood == nil ? 1.8 : 3.2
        if f.species == .crab && f.feeding == nil {
            let gait = f.crabGait.velocityFactor
            desiredVX += gait.x * f.species.cruiseSpeed * f.personality.boldness
            desiredVY += gait.y * f.species.cruiseSpeed * f.personality.boldness
            // Crab legs start and stop a burst almost at once.
            responseRate = 25
        } else if f.species == .shrimp && f.feeding == nil {
            responseRate = 8
        }
        let response = 1 - exp(-movement * responseRate)
        if f.species == .crab {
            crawl(&f, desiredVX: desiredVX, desiredVY: desiredVY, response: response, movement: movement)
        } else if f.species == .shrimp && f.shrimpBehavior.isEscaping {
            tailFlip(&f, movement: movement)
        } else {
            glide(&f, desiredVX: desiredVX, desiredVY: desiredVY, response: response, movement: movement)
        }
        (f.x, f.y) = goal.region.constrain(x: f.x, y: f.y)
        let actualSpeed = hypot(f.vx, f.vy)
        f.stroke.advance(delta: movement, species: f.species, speed: actualSpeed / f.species.cruiseSpeed,
            acceleration: (actualSpeed - previousSpeed) / (movement * f.species.cruiseSpeed),
            turnRate: Self.angleDifference(f.yaw, previousYaw) / movement,
            turnAcceleration: (f.yawVelocity - previousYawVelocity) / movement,
            hovering: f.isHovering)
        if f.species == .crab {
            // Crab legs step in proportion to the distance walked, and the gait clock runs
            // backward continuously as travel reverses; flipping a sign in the shader would
            // snap all eight feet.
            let stride = ((f.vx + f.vy * 0.45) / f.species.cruiseSpeed).clamped(to: -4.5...4.5)
            f.finPhase += movement * Self.crabStepsPerCruise * stride
        } else if f.species == .shrimp {
            // About one and a half steps a second while walking; a slow idle between steps.
            f.finPhase += movement * (f.shrimpBehavior.stepping || f.feeding != nil ? Self.shrimpStepRate : Self.shrimpStepRate * 0.15)
        } else {
            f.finPhase += movement * f.stroke.tailRate
        }
    }

    /// A burst of tail flips away from the threat: each flip is a sharp jerk backward and
    /// upward that dies away before the next. From a threat ahead the shrimp goes tail first;
    /// from a threat behind it darts forward; with no room either side it shoots straight up.
    private func tailFlip(_ f: inout FishState, movement: Double) {
        let behavior = f.shrimpBehavior
        let end = min(behavior.escapeDuration, behavior.escapeDuration - behavior.escapeRemaining)
        let start = max(0, end - movement)
        // Each flip is a jerk that dies away exponentially and covers exactly `flipDistance` body
        // lengths. Integrating the travel over the frame keeps that true at any frame rate.
        let decay = 4.0
        let flip = ShrimpBehavior.flipDuration
        func travelled(_ t: Double) -> Double {
            let flips = (t / flip).rounded(.down)
            let within = (t - flips * flip) / flip
            return (flips + (1 - exp(-decay * within)) / (1 - exp(-decay))) * Self.flipDistance * f.species.bodyLength
        }
        let distance = travelled(end) - travelled(start)
        f.forwardSpeed = 0
        let direction = behavior.escapeDirection
        // Distance is in scene widths; vertical travel is measured in scene heights.
        f.vx = direction * distance * 0.82 / movement
        f.vy = distance * TankScale.aspect * (direction == 0 ? 1 : 0.57) / movement
        f.x += f.vx * movement
        f.y += f.vy * movement
    }

    /// Crabs walk in any direction and only angle their shell gently toward it.
    private func crawl(_ f: inout FishState, desiredVX: Double, desiredVY: Double, response: Double, movement: Double) {
        f.vx += (desiredVX - f.vx) * response
        f.vy += (desiredVY - f.vy) * response
        let targetYaw = sin(atan2(desiredVY, desiredVX)) * 0.35 + f.navigation.viewAngle * 0.5
        let requested = max(-0.65, min(0.65, Self.angleDifference(targetYaw, f.yaw) * 1.8))
        f.yawVelocity += (requested - f.yawVelocity) * (1 - exp(-movement * 10))
        f.yaw += f.yawVelocity * movement
        f.x += f.vx * movement
        f.y += f.vy * movement
    }

    /// Fish and shrimp swim along their body axis. A reversal is a banked U-turn: the fish
    /// keeps gliding forward while its heading swings through a three-quarter and head-on
    /// view, so the path curves into or out of the scene instead of spinning in place.
    private func glide(_ f: inout FishState, desiredVX: Double, desiredVY: Double, response: Double, movement: Double) {
        chooseFacing(&f, desiredVX: desiredVX, movement: movement)
        let targetYaw = (f.facingRight ? 0 : Double.pi) + (f.isChasingFood ? 0 : f.navigation.viewAngle)
        var turnLimit = (f.isChasingFood ? Self.feedingTurnLimit : f.navigation.turnLimit) * f.species.turnAgility
        // Gouramis and bettas can hover and rotate slowly on their fins with a nearly straight body.
        let hoverTurn = f.isHovering
        if hoverTurn {
            // Fin-powered hover turns are slow but do not linger edge-on.
            turnLimit = min(turnLimit, Self.hoverTurnRate)
        } else if !f.isChasingFood && !f.species.isInvertebrate {
            // A body cannot turn tighter than its species' radius, so large fish swing through
            // a visible arc while small, quick ones flick round.
            let radius = f.species.turnRadius * f.species.bodyLength
            turnLimit = min(turnLimit, max(Self.stationaryTurnRate, f.forwardSpeed / radius))
        }
        if (f.species == .loach || f.species == .shrimp) && abs(cos(f.yaw)) < 0.3 {
            // A side-on photograph cannot show these from the front, so they swing through that
            // view quickly rather than lingering on it.
            turnLimit *= f.species == .shrimp ? Self.headOnHurry * 2 : Self.headOnHurry
        }
        let difference = bankedDifference(&f, to: targetYaw, movement: movement)
        let requested = max(-turnLimit, min(turnLimit, difference * Self.turnGain))
        let angularStep = movement * Self.maximumTurnAcceleration
        f.yawVelocity += max(-angularStep, min(angularStep, (requested - f.yawVelocity) * (1 - exp(-movement * Self.turnResponse))))
        f.yaw = atan2(sin(f.yaw + f.yawVelocity * movement), cos(f.yaw + f.yawVelocity * movement))

        // Full speed only once the body points where the fish wants to go. Fish also slow
        // a little in a tight turn, then accelerate out of it.
        let alignment = cos(f.yaw) * (desiredVX >= 0 ? 1 : -1)
        let glide = max(f.isChasingFood ? Self.feedingGlide : Self.wanderingGlide, alignment)
        let turning = min(1, abs(f.yawVelocity) / FishNavigation.turnLimits.upperBound)
        var forwardTarget = abs(desiredVX) * glide * (1 - 0.3 * turning)
        let turningAround = abs(cos(f.yaw)) < 0.5 || abs(Self.angleDifference(targetYaw, f.yaw)) > 1
        if !f.isChasingFood && turningAround && !f.species.isInvertebrate && !hoverTurn {
            // Even a slow fish swims through a turn rather than pivoting on the spot, pushing a
            // little harder (up to `turnSurge` times its cruise speed); beyond that, large fish
            // swing wider and slower instead of speeding up.
            let turnSpeed = f.navigation.turnLimit * f.species.turnAgility * f.species.turnRadius * f.species.bodyLength
            forwardTarget = max(forwardTarget, f.species.cruiseSpeed * 0.35, min(turnSpeed, f.species.cruiseSpeed * f.species.turnSurge))
        }
        // Rising or diving, a fish swims forward along the slope instead of lifting straight up.
        // When the goal is nearly straight above or below, either facing will do.
        let mostlyVertical = abs(desiredVY) > abs(desiredVX) * 2
        let slopeAlignment = mostlyVertical ? abs(cos(f.yaw)) : alignment
        if !f.species.isInvertebrate && slopeAlignment > 0 {
            forwardTarget = max(forwardTarget, abs(desiredVY) * 0.5 * slopeAlignment)
        }
        // A fish that spots food behind it brakes hard instead of coasting away.
        let braking = f.isChasingFood && alignment < 0 && !mostlyVertical ? 1 - exp(-movement * 12) : response
        f.forwardSpeed += (forwardTarget - f.forwardSpeed) * max(response, braking)
        var vy = f.vy + (desiredVY - f.vy) * response
        if !f.isChasingFood && !f.species.isInvertebrate {
            // A fish climbs or dives along a gentle slope, never straight up like a lift.
            let climb = max(f.forwardSpeed * 0.6, f.species.cruiseSpeed * 0.15)
            vy = max(-climb, min(climb, vy))
        }
        f.vy = vy
        if f.species == .shrimp, !f.shrimpBehavior.isEscaping, let theme,
           f.y > Self.region(for: .shrimp, theme: theme).top
            || (f.shrimpBehavior.phase == .grazing && f.feeding == nil
                && f.y > ShrimpBehavior.bedTop(of: Self.region(for: .shrimp, theme: theme)) + 0.004) {
            // After an escape the shrimp sinks back down to its usual band.
            f.vy = min(f.vy, -TankScale.height(cm: 1.5))
        }
        if f.species == .shrimp && f.feeding == nil && f.shrimpBehavior.holdsPosition {
            // Hidden shrimp stay put; emerging ones ease out of the refuge.
            let damping = f.shrimpBehavior.phase == .hidden ? 0 : exp(-movement * 12)
            f.forwardSpeed *= damping
            f.vy *= damping
        }
        f.vx = f.forwardSpeed * cos(f.yaw)
        f.x += f.vx * movement
        f.y += f.vy * movement
        // yaw π/2 faces away from the viewer, so forward travel then carries the fish farther away.
        f.depth -= f.forwardSpeed * sin(f.yaw) * movement * Self.depthTravel
        // Drift back to the usual depth only while side-on, so it never cancels a turn's travel.
        f.depth += (f.homeDepth - f.depth) * (1 - exp(-movement * 0.4 * cos(f.yaw) * cos(f.yaw)))
        // Bed residents keep to their own depth band; others roam the full depth of the tank.
        f.depth = f.depth.clamped(to: f.species.isBottomDweller ? Self.birthDepths(for: f.species) : FishState.depthRange)

        let pitchTarget = FishState.pitchTarget(species: f.species, vx: f.vx, vy: f.vy, yawRate: f.yawVelocity, chasing: f.isChasingFood)
        let pitchStep = (pitchTarget - f.pitch) * (1 - exp(-movement * 3.0))
        f.pitch += max(-movement * 0.35, min(movement * 0.35, pitchStep))
    }

    /// Only a clear, lasting horizontal intent changes the side a fish faces, so small
    /// corrections while hovering or nibbling never trigger a turn, and a turn that has
    /// begun is finished rather than abandoned halfway.
    private func chooseFacing(_ f: inout FishState, desiredVX: Double, movement: Double) {
        let side = f.facingRight ? 1.0 : -1.0
        let opposing = desiredVX * side < -f.species.cruiseSpeed * Self.facingThreshold
        let midTurn = cos(f.yaw) * side < 0
        // While nibbling, the goal is the fish's own position; spacing nudges must not spin it.
        let nibbling = f.feeding?.phase == .nibbling
        guard opposing && !midTurn && !nibbling else { f.reversalUrge = 0; return }
        f.reversalUrge += movement
        if f.reversalUrge >= (f.isChasingFood ? Self.feedingReversalPatience : Self.reversalPatience) {
            f.facingRight.toggle()
            f.reversalUrge = 0
            // A new turn chooses its own direction; keeping the old one would spin the fish full circle.
            if f.turnDirection != 0 { f.lastTurnDirection = f.turnDirection; f.sinceLastTurn = 0 }
            f.turnDirection = 0
        }
    }

    /// Angle still to turn. A reversal picks, once, whether to swing away from or toward
    /// the viewer: a fish near the glass turns away, a distant one turns toward us. That
    /// keeps depth changing, so the fish never sits pinned at a depth limit spinning in place.
    /// A reversal soon after another unwinds the other way instead.
    private func bankedDifference(_ f: inout FishState, to targetYaw: Double, movement: Double) -> Double {
        var difference = Self.angleDifference(targetYaw, f.yaw)
        f.sinceLastTurn += movement
        if abs(difference) < 0.3 && f.turnDirection != 0 {
            f.lastTurnDirection = f.turnDirection
            f.sinceLastTurn = 0
            if !f.isHovering { f.stroke.sweepTailBack(turn: f.turnDirection, species: f.species) }
            f.turnDirection = 0
        }
        if f.turnDirection == 0 && abs(difference) > Self.bankingAngle {
            let range = FishState.depthRange
            let shortWay: Double = difference < 0 ? -1 : 1
            // Halfway through a turn, sin(yaw) > 0 means the fish faces away from the viewer.
            let shortWayGoesAway = sin(f.yaw + difference / 2) > 0
            if abs(f.yawVelocity) > 0.05 {
                // Still rotating from the last turn: swing back rather than loop round into a pinwheel.
                f.turnDirection = f.yawVelocity > 0 ? -1 : 1
            } else if f.isChasingFood {
                // Food is worth the quickest turn.
                f.turnDirection = shortWay
            } else if f.sinceLastTurn < Self.unwindWindow && f.lastTurnDirection != 0 {
                f.turnDirection = -f.lastTurnDirection
            } else {
                let turnAway = f.depth > (range.lowerBound + range.upperBound) / 2
                f.turnDirection = shortWayGoesAway == turnAway ? shortWay : -shortWay
            }
        }
        if f.turnDirection != 0 && difference * f.turnDirection < 0 {
            if abs(difference) > .pi / 2 {
                // Still early in the turn: keep going the chosen way round.
                difference += 2 * .pi * f.turnDirection
            } else {
                // Momentum carried the fish just past its heading; the turn is done.
                f.lastTurnDirection = f.turnDirection
                f.sinceLastTurn = 0
                if !f.isHovering { f.stroke.sweepTailBack(turn: f.turnDirection, species: f.species) }
                f.turnDirection = 0
            }
        }
        return difference
    }

    private mutating func eatIfReached(_ f: inout FishState, targetFood: Int?) {
        guard let targetFood, let pellet = food.first(where: { $0.id == targetFood }) else { return }
        let snout = f.species.bodySize * f.depth / 2300 * (f.species == .shrimp ? 0.18 : 0.35)
        let mouthX = f.x + (f.species == .crab ? 0 : cos(f.yaw) * snout)
        guard hypot(pellet.x - mouthX, (pellet.y - f.y) * 0.55) < Self.mouthReach else { return }
        food.removeAll { $0.id == targetFood }
        mealsEaten += 1
        // Taking food off the bottom throws up a puff of sand.
        if pellet.y <= Self.sandHeight + 0.004 {
            sand.puff(x: pellet.x, floor: pellet.y, depth: pellet.depth.clamped(to: FishState.depthRange), strength: 1)
        }
        f.appetite = max(0, f.appetite - 0.7)
        f.feeding = FeedingResponse(phase: .nibbling, targetID: nil, x: f.x, y: f.y, remaining: f.dice.value(0.65...1.0))
    }
}
