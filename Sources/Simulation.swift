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
    /// The same travel on the sand bed, where going farther back means moving up the picture.
    static let bedTravel = 1.0
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
    /// How far each foot sweeps back while planted, in photo texture units; must match the
    /// `crabStride` constant in the crab shader so feet stay fixed to the sand.
    static let crabStride = 0.2
    /// A stride toward or away from the viewer is drawn foreshortened to this share of its length.
    static let crabVerticalStride = 0.5
    /// Share of each step cycle a foot spends planted (stance), also shared with the shader.
    static let crabStance = 0.6
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
            // The open sand, from near the glass (bottom of the picture) back toward the rocks.
            case .grove: bed = SwimRegion(left: 0.47, right: 0.90, bottom: 0.045, top: 0.14)
            case .river: bed = SwimRegion(left: 0.14, right: 0.63, bottom: 0.045, top: 0.16)
            case .spring: bed = SwimRegion(left: 0.30, right: 0.64, bottom: 0.045, top: 0.115)
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
            if fish[i].species.isBottomDweller {
                let bedTop = Self.region(for: .loach, theme: configuration.theme).top
                fish[i].depth = Self.bedDepth(y: min(fish[i].y, bedTop), theme: configuration.theme)
            }
        }
    }

    /// On the sand floor, depth follows height in the picture: a resident lower on the bed is
    /// nearer the glass and drawn larger, one higher up is farther back and smaller.
    static func bedDepth(y: Double, theme: AquariumTheme) -> Double {
        let bed = region(for: .loach, theme: theme)
        let t = ((y - bed.bottom) / max(0.001, bed.height)).clamped(to: 0...1)
        return FishState.depthRange.upperBound - t * (FishState.depthRange.upperBound - FishState.depthRange.lowerBound)
    }

    /// Every individual owns independent random streams derived from its identity.
    private mutating func makeFish(_ species: FishSpecies, in region: SwimRegion) -> FishState {
        let personalSeed = entitySeed ^ (UInt64(nextID) &* 0x9E3779B97F4A7C15)
        var birth = Dice(seed: personalSeed ^ 0xB17A)
        let facingRight = birth.chance(0.5)
        var resident = FishState(id: nextID, species: species,
            x: birth.value(region.left...region.right), y: birth.value(region.bottom...region.top),
            depth: birth.value(FishState.depthRange), facingRight: facingRight,
            finPhase: birth.value(0...6), moodRemaining: birth.value(1...10))
        resident.personality = Personality(dice: &birth)
        resident.stroke = FishStroke(seed: personalSeed ^ 0xF1A5)
        resident.navigation = FishNavigation(seed: personalSeed ^ 0xA11CE, heading: facingRight ? 0 : .pi,
                                             personality: resident.personality, flatness: species.isBottomDweller ? 0.35 : 1)
        resident.dice = Dice(seed: personalSeed ^ 0xBEA710)
        resident.shrimpBehavior = ShrimpBehavior(seed: personalSeed ^ 0x5A11)
        resident.crabGait = CrabGait(seed: personalSeed ^ 0xC2AB)
        resident.burst = BurstRhythm(seed: personalSeed ^ 0xB0257)
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
        if f.species == .loach {
            f.burst.advance(delta: movement)
            // A loach that needs to turn around sets off and swims round rather than spinning in
            // place, and keeps swimming until the turn is done.
            let turnLeft = abs(Self.angleDifference(f.facingRight ? 0 : .pi, f.yaw))
            if f.feeding == nil {
                if !f.burst.moving && turnLeft > 1 { f.burst.startBurst() }
                // A turn-around swims back into the lane it came from; only a dart straight
                // ahead is checked against the neighbours in that lane.
                let wasSidestepping = f.burst.sidestepping
                if turnLeft > 0.5 && !f.burst.sidestepping { f.burst.hold(0.15) } else { keepDartLaneClear(&f, home: home, movement: movement) }
                // A sidestep ends where it ends, without a lurch forward as the drive dies away.
                if wasSidestepping && !f.burst.moving { f.activity = min(f.activity, 0.4) }
                if f.burst.moving && !f.burst.justSetOff { f.parkedFor = 0 } else { f.parkedFor += movement }
            }
            f.siftClock += movement
            let sifting = f.feeding == nil && !f.burst.moving && f.mood != .hover
            // The head goes down gently once a pause begins, and comes up at once to swim off.
            f.siftEnvelope += ((sifting ? 1 : 0) - f.siftEnvelope) * (1 - exp(-dt * (sifting ? 4 : 25)))
        }
        if f.species == .crab {
            f.crabGait.advance(delta: movement, x: f.x, y: f.y, region: home)
            // (A sidestep up or down the bed is not blocked by what lies to either side.)
            if f.crabGait.walking {
                let direction = f.crabGait.direction
                let blocked = abs(cos(direction)) > 0.5 ? isBlockedOnBed(f, heading: cos(direction))
                    : !bedIsClearAcross(f, up: sin(direction) > 0, home: home)
                if blocked { f.crabGait.bumped() }
            }
            // Away from food, the gait alone decides where a crab walks.
            if f.feeding == nil { goal.x = f.x; goal.y = f.y }
        }
        let desiredActivity = activityTarget(for: f)
        // Shrimp legs and loach wriggles start and stop quickly; other fish ease between moods.
        let activityRate = f.feeding != nil ? 3.5 : (f.species == .shrimp ? 12.0 : (f.species == .loach ? 10.0 : 3.5))
        f.activity += (desiredActivity - f.activity) * (1 - exp(-movement * activityRate))
        let (dx, dy) = steeringVector(for: f, towards: goal)
        let startX = f.x, startY = f.y
        swim(&f, dx: dx, dy: dy, goal: goal, movement: movement)
        if f.species.isBottomDweller { f.depth = Self.bedDepth(y: min(f.y, home.top), theme: theme) }
        if f.species.isBottomDweller { nudgeApartOnBed(&f, region: goal.region, movement: movement) }
        if f.species == .crab { stepCrabLegs(&f, dx: f.x - startX, dy: f.y - startY, dt: dt, movement: movement) }
        eatIfReached(&f, targetFood: goal.targetFood)
        stirSand(f, previousBouts: previousBouts, wasStepping: wasStepping, movement: movement)
    }

    /// The leg cycle advances exactly with the distance the crab actually moved, nudges and edges
    /// included: during stance a foot sweeps back along the leg axis by the same amount the body
    /// moves forward, so planted feet never slide. The gait clock runs backward as travel
    /// reverses; flipping a sign in the shader would snap all eight feet.
    private func stepCrabLegs(_ f: inout FishState, dx: Double, dy: Double, dt: Double, movement: Double) {
        let photoUnit = f.species.sceneWidthPerPhotoUnit * f.depth
        // Travel in photo units; a scene height is 1/aspect of a scene width on screen.
        let tx = dx / photoUnit, ty = dy / TankScale.aspect / photoUnit
        let travel = hypot(tx, ty)
        if travel > 1e-9 {
            // The axis turns toward the travel line, keeping its sense so reversals run the gait backward.
            var ax = tx / travel, ay = ty / travel
            if ax * f.legAxisX + ay * f.legAxisY < 0 { ax = -ax; ay = -ay }
            let turn = 1 - exp(-movement * 8)
            let nx = f.legAxisX + (ax - f.legAxisX) * turn, ny = f.legAxisY + (ay - f.legAxisY) * turn
            let length = max(1e-6, hypot(nx, ny))
            f.legAxisX = nx / length; f.legAxisY = ny / length
        }
        // Vertical travel is drawn foreshortened, so the legs cycle further for it.
        let along = tx * f.legAxisX + ty * f.legAxisY / Self.crabVerticalStride
        // Capped below half a cycle per update, so even at the fastest settings the legs never strobe.
        let step = along / (Self.crabStride / Self.crabStance) * 2 * .pi
        f.finPhase += step.clamped(to: -0.9 * .pi...0.9 * .pi)
        // Standing still, lifted feet come down within about a tenth of a second of real time.
        let speed = travel / max(movement, 1e-6) * photoUnit
        let standing = speed < f.species.cruiseSpeed * 0.2
        f.legSettle += ((standing ? 1 : 0) - f.legSettle) * (1 - exp(-dt * (standing ? 15 : 30)))
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

    /// Vertical separation of two bed residents on screen.
    static func bedGap(_ y: Double, _ depth: Double, _ otherY: Double, _ otherDepth: Double) -> Double { y - otherY }

    /// A crab and another bed resident: crabs never settle over a loach or shrimp, at any depth,
    /// because their splayed legs would seem to stand on it.
    static func crabAndLoach(_ a: FishSpecies, _ b: FishSpecies) -> Bool {
        a == .crab || b == .crab
    }

    /// Pairs that must never overlap on screen, whatever their depth: crabs with anyone, and
    /// loaches with each other, which would otherwise line up nose to tail and read as one fish.
    static func keepApartAtAnyDepth(_ a: FishSpecies, _ b: FishSpecies) -> Bool {
        crabAndLoach(a, b) || (a == .loach && b == .loach)
    }

    /// How far apart two bed residents must be up and down the screen: a crab's legs reach well
    /// above and below its shell.
    static func bedReachY(_ a: FishSpecies, _ b: FishSpecies) -> Double {
        crabAndLoach(a, b) ? 0.035 : 0.02
    }

    /// A crab heading for food with another crab already between it and the food, close by.
    private func isQueuedBehind(_ f: FishState, food: FeedingResponse) -> Bool {
        let mine = hypot(food.x - f.x, food.y - f.y)
        return neighbors.contains { other in
            other.id != f.id && other.species == .crab
                && hypot(food.x - other.x, food.y - other.y) < mine
                && hypot(other.x - f.x, (other.y - f.y) * 0.5) < f.species.bedFootprint * f.depth * 1.1
        }
    }

        /// A loach never darts into a neighbour. Setting off with someone close ahead in its lane, it
    /// goes the other way if that lane is clear, or takes a short hop toward whichever side has
    /// more room; boxed in on both sides for long, it sidesteps to another lane. A neighbour
    /// moving into the lane during a dart ends the dart, and the loach coasts to a stop short of it.
    private func keepDartLaneClear(_ f: inout FishState, home: SwimRegion, movement: Double) {
        guard f.burst.moving else { return }
        let ahead = f.facingRight ? 1.0 : -1.0
        let length = f.species.bodyLength * f.depth
        if f.burst.justSetOff {
            guard bedFreeDistance(f, heading: ahead) < length * 0.8 else { return }
            // Turning back needs clear sand behind, including beside the lane, and a loach that
            // has just turned does not turn straight back again.
            // A loach boxed in for a long while turns back at the first chance, whatever it did last.
            let boxedLong = f.parkedFor > 3
            if bedFreeDistance(f, heading: -ahead, lane: boxedLong ? 0.025 : 0.04) >= length * 0.8 && (f.sinceLastTurn > 2.5 || boxedLong) {
                turnBack(&f)
                return
            }
            // Otherwise step across to another lane, toward the side with more sand if it is
            // clear, else the other side; boxed in on both, wait. Boxed in for long, it squeezes
            // through a narrower gap, and at last turns back and swims round regardless.
            let up = f.y < (home.top + home.bottom) / 2
            let margin = boxedLong ? 0.018 : 0.03
            if bedIsClearAcross(f, up: up, home: home, margin: margin) {
                f.burst.sidestep(up: up)
            } else if bedIsClearAcross(f, up: !up, home: home, margin: margin) {
                f.burst.sidestep(up: !up)
            } else if f.parkedFor > 6 {
                turnBack(&f)
            } else {
                f.burst.stop()
            }
        } else if f.burst.sidestepping {
            // A sidestep stops short of anyone lying in the lane it is moving into.
            if !bedIsClearAcross(f, up: f.burst.bearing > 0, home: home, margin: 0.02) { f.burst.stop() }
        } else if bedFreeDistance(f, heading: ahead, lane: abs(f.burst.bearing) > 0.3 ? 0.04 : nil) < length * 0.8 {
            // Coasting to a stop covers about a third of a body length; a dart veering across
            // the bed also minds the next lane.
            f.burst.stop()
        }
    }

    /// Whether a bed resident can move `up` (or down) the bed without landing on a neighbour:
    /// nobody overlapping it side to side lies within `margin` (a crab: half as much again) in
    /// that direction.
    private func bedIsClearAcross(_ f: FishState, up: Bool, home: SwimRegion, margin: Double = 0.03) -> Bool {
        let room = up ? home.top - f.y : f.y - home.bottom
        guard room > 0.03 else { return false }
        return !neighbors.contains { other in
            guard other.id != f.id, other.species.isBottomDweller else { return false }
            let reach = (f.species.bedFootprint * f.depth + other.species.bedFootprint * other.depth) * 0.5
            guard abs(other.x - f.x) < reach else { return false }
            let gap = Self.bedGap(other.y, other.depth, f.y, f.depth) * (up ? 1 : -1)
            return gap > -0.01 && gap < margin * (other.species == .crab ? 1.5 : 1)
        }
    }

    private func turnBack(_ f: inout FishState) {
        f.facingRight.toggle()
        f.navigation.turnBack()
        f.reversalUrge = 0
        if f.turnDirection != 0 { f.lastTurnDirection = f.turnDirection; f.sinceLastTurn = 0 }
        f.turnDirection = 0
    }

    /// Whether `other` lies in the same lane on the bed as `f`: a loach gives a crab a wider berth
    /// than another loach, and a crab a loach likewise.
    private static func sharesLane(_ f: FishState, _ other: Neighbor, lane: Double? = nil) -> Bool {
        guard other.species.isBottomDweller,
              abs(other.depth - f.depth) < bedLayer || crabAndLoach(f.species, other.species) else { return false }
        let tolerance = lane ?? (crabAndLoach(f.species, other.species) && f.species != other.species ? 0.035
            : (f.species == .loach && other.species == .loach ? 0.025 : 0.015))
        return abs(bedGap(f.y, f.depth, other.y, other.depth)) < tolerance
    }

    /// Clear sand ahead of `f` in its lane before the nearest neighbour's edge, in scene widths.
    private func bedFreeDistance(_ f: FishState, heading: Double, lane: Double? = nil) -> Double {
        neighbors.reduce(Double.infinity) { free, other in
            guard other.id != f.id, Self.sharesLane(f, other, lane: lane) else { return free }
            let reach = (f.species.bedFootprint * f.depth + other.species.bedFootprint * other.depth) * 0.5
            let ahead = (other.x - f.x) * heading
            return ahead > 0 ? min(free, ahead - reach) : free
        }
    }

    /// Whether a neighbour on the bed lies just ahead, within `lookahead` beyond touching. A loach
    /// gives a crab a wider berth, so it never slips under the crab's legs.
    private func isBlockedOnBed(_ f: FishState, heading: Double, lookahead: Double = 0) -> Bool {
        neighbors.contains { other in
            guard other.id != f.id, Self.sharesLane(f, other) else { return false }
            let reach = (f.species.bedFootprint * f.depth + other.species.bedFootprint * other.depth) * 0.5 + lookahead
            let ahead = (other.x - f.x) * heading
            return ahead > 0 && ahead < reach
        }
    }

    /// Residents lying on the bed that touch at the same depth slide gently apart along the sand,
    /// whichever way they face, as bodies bump and settle side by side.
    /// How far apart side to side, as a share of their footprints, bottom dwellers keep. Loaches
    /// keep a little more room, so two never read as one long fish lying nose to tail, but crowd
    /// in at food.
    static func bedReachX(_ a: FishSpecies, _ b: FishSpecies, feeding: Bool = false) -> Double {
        if feeding { return 0.9 }
        if a == .loach && b == .loach { return 1.35 }
        // A loach keeps its snout clear of a crab's spread legs.
        if crabAndLoach(a, b) && (a == .loach || b == .loach) { return 1.1 }
        return 0.9
    }

    /// How far apart two bed residents are, as a share of the room they keep (1 = just clear).
    /// A loach and a crab keep a box of room, so a loach never lies diagonally with its snout
    /// across the crab's spread legs; other pairs keep an ellipse.
    static func bedSeparation(_ a: FishSpecies, _ b: FishSpecies, _ x: Double, _ y: Double) -> Double {
        crabAndLoach(a, b) && a != b ? max(abs(x), abs(y)) : hypot(x, y)
    }

    /// A crab away from food holds its ground; a loach that meets it goes round it, and is not
    /// the one to shove the crab along.
    private func holdsGround(_ f: FishState, against other: Neighbor) -> Bool {
        f.species == .crab && f.feeding == nil && other.species == .loach
    }

    private func nudgeApartOnBed(_ f: inout FishState, region: SwimRegion, movement: Double) {
        // A shrimp tucked into its refuge is not shouldered out of it; neighbours make the room.
        if f.species == .shrimp && f.feeding == nil && f.shrimpBehavior.holdsPosition { return }
        var push = 0.0
        for other in neighbors where other.id != f.id && other.species.isBottomDweller && !holdsGround(f, against: other)
            && (abs(other.depth - f.depth) < Self.bedLayer || Self.keepApartAtAnyDepth(f.species, other.species)) {
            let reachX = (f.species.bedFootprint * f.depth + other.species.bedFootprint * other.depth) * 0.5 * Self.bedReachX(f.species, other.species, feeding: f.isChasingFood)
            let sx = f.x - other.x, sy = Self.bedGap(f.y, f.depth, other.y, other.depth)
            let gap = Self.bedSeparation(f.species, other.species, sx / reachX, sy / Self.bedReachY(f.species, other.species))
            guard gap < 1 else { continue }
            let side: Double = sx != 0 ? (sx > 0 ? 1 : -1) : (f.id < other.id ? -1 : 1)
            push += side * (1 - gap)
        }
        guard push != 0 else { return }
        if f.species == .crab, let food = f.feeding, food.phase == .approaching, push * (food.x - f.x) < 0 {
            // A crab crowded at food waits its turn rather than being shoved back from it.
            return
        }
        // A resident heading for food only shoulders its neighbours aside gently.
        let nudge = f.isChasingFood ? Self.bedNudge * 0.3 : Self.bedNudge
        f.x += push.clamped(to: -1...1) * f.species.cruiseSpeed * nudge * movement
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
        if f.species == .loach && f.feeding == nil && f.mood != .hover {
            // Wriggle forward in a burst, then stop dead to sift before the next one.
            // A dart is strongest at the start and eases off, rather than cruising at one speed.
            return f.burst.moving ? 10 * (0.55 + 0.45 * exp(-f.burst.elapsed / 0.45)) : 0.02
        }
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
                guard abs(other.depth - f.depth) < Self.bedLayer || Self.keepApartAtAnyDepth(f.species, other.species),
                      !holdsGround(f, against: other) else { continue }
                let reachX = (f.species.bedFootprint * f.depth + other.species.bedFootprint * other.depth) * 0.5 * Self.bedReachX(f.species, other.species, feeding: f.isChasingFood)
                let reachY = Self.bedReachY(f.species, other.species)
                let bedY = Self.bedGap(f.y, f.depth, other.y, other.depth)
                let gap = Self.bedSeparation(f.species, other.species, sx / reachX, bedY / reachY)
                if gap < 1 {
                    // While feeding they crowd in, but never lie right on top of one another.
                    let feedingPush = Self.crabAndLoach(f.species, other.species) ? (f.species == other.species ? 0.12 : 0.2)
                        : (f.species == .loach && other.species == .loach ? 0.06 : (gap < 0.6 ? 0.08 : 0.025))
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
        // A wriggling loach keeps its pace however close its next spot on the bed is.
        let throttle = f.species == .loach && f.feeding == nil && f.burst.moving ? 1 : min(1, distance / 0.025)
        let speed = f.species.cruiseSpeed * f.activity * pace * throttle
        var desiredVX = dx / distance * speed, desiredVY = dy / distance * speed
        if f.species == .loach && f.feeding == nil && f.burst.moving {
            // Each dart veers a little, so the path over the sand arcs rather than running on rails.
            if f.burst.sidestepping {
                // A sidestep heads straight up or down the bed, whichever way the loach faces.
                (desiredVX, desiredVY) = (0, (f.burst.bearing > 0 ? 1 : -1) * hypot(desiredVX, desiredVY))
            } else {
                let c = cos(f.burst.bearing), s = sin(f.burst.bearing)
                (desiredVX, desiredVY) = (desiredVX * c - desiredVY * s, desiredVX * s + desiredVY * c)
            }
        }
        let previousSpeed = hypot(f.vx, f.vy)
        let previousYaw = f.yaw, previousYawVelocity = f.yawVelocity
        var responseRate = goal.targetFood == nil ? 1.8 : 3.2
        if f.species == .crab && f.feeding == nil {
            let gait = f.crabGait.velocityFactor
            // The body surges a little with each step rather than gliding at an even speed.
            let surge = 1 + 0.15 * sin(f.finPhase * 2)
            desiredVX += gait.x * f.species.cruiseSpeed * f.personality.boldness * surge
            desiredVY += gait.y * f.species.cruiseSpeed * f.personality.boldness * surge
            // Crab legs start and stop a burst almost at once.
            responseRate = 25
        } else if f.species == .shrimp && f.feeding == nil {
            responseRate = 8
        } else if f.species == .loach && f.feeding == nil {
            // A loach stops dead to sift rather than coasting.
            responseRate = 14
        }
        let response = 1 - exp(-movement * responseRate)
        if f.species == .crab, let food = f.feeding, food.phase == .approaching, isQueuedBehind(f, food: food) {
            // Another crab is nearer the same food and in the way: stand and wait rather than jostle.
            desiredVX = 0; desiredVY = 0
        }
        if f.species == .crab {
            crawl(&f, desiredVX: desiredVX, desiredVY: desiredVY, response: response, movement: movement)
        } else if f.species == .shrimp && f.shrimpBehavior.isEscaping {
            tailFlip(&f, movement: movement)
        } else {
            glide(&f, desiredVX: desiredVX, desiredVY: desiredVY, response: response, movement: movement)
        }
        (f.x, f.y) = goal.region.constrain(x: f.x, y: f.y)
        let actualSpeed = hypot(f.vx, f.vy)
        // A loach coasting out of a dart holds its body straight; the wriggle is only for driving.
        let coasting = f.species == .loach && f.feeding == nil && !f.burst.moving
        f.stroke.advance(delta: movement, species: f.species, speed: actualSpeed / f.species.cruiseSpeed * (coasting ? 0.3 : 1),
            acceleration: (actualSpeed - previousSpeed) / (movement * f.species.cruiseSpeed),
            turnRate: Self.angleDifference(f.yaw, previousYaw) / movement,
            turnAcceleration: (f.yawVelocity - previousYawVelocity) / movement,
            hovering: f.isHovering, restingBend: f.species == .loach && f.feeding == nil && !f.burst.moving ? f.burst.restBend : 0)
        if f.species == .crab {
            // Crab legs step in proportion to the distance walked (see `stepCrabLegs`).
        } else if f.species == .shrimp {
            // About one and a half steps a second while walking; a slow idle between steps.
            f.finPhase += movement * (f.shrimpBehavior.stepping || f.feeding != nil ? Self.shrimpStepRate : Self.shrimpStepRate * 0.15)
        } else if f.species == .loach {
            // Anguilliform swimming: the body wave travels back a little faster than the fish moves
            // forward, about one and a half waves per body length, plus a slow ripple at rest.
            // A burst adds a quick beat of its own: a kuhli loach wriggles at two to three waves a second.
            let travelled = hypot(f.vx, f.vy) * movement / (f.species.bodyLength * f.depth)
            f.finPhase += travelled * 2 * .pi * 1.5 + movement * 0.35 + movement * 2 * .pi * 2 * min(1, f.activity / 2)
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
        // A resting loach lies at a slight angle of its own rather than parallel to its neighbours.
        let restingLoach = f.species == .loach && f.feeding == nil && !f.burst.moving
        // Stepping across to another lane, a loach angles its body toward it and crawls diagonally.
        let acrossYaw = f.species == .loach && f.feeding == nil && f.burst.sidestepping
            ? (f.burst.bearing > 0 ? 0.5 : -0.5) * (f.facingRight ? 1 : -1) : 0
        let targetYaw = (f.facingRight ? 0 : Double.pi) + (f.isChasingFood ? 0 : f.navigation.viewAngle) + (restingLoach ? f.burst.restYaw : 0) + acrossYaw
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
            // A bursting loach whips round in a tight C, as eels do.
            if f.species == .loach && f.feeding == nil && f.burst.moving { turnLimit *= 1.8 }
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
        let bursting = f.species == .loach && f.feeding == nil && f.burst.moving
        if bursting {
            // A wriggling loach drives forward at the burst's full pace, and keeps swimming through a turn.
            let drive = hypot(desiredVX, desiredVY) * max(0.5, alignment)
            forwardTarget = min(max(forwardTarget, drive), f.species.cruiseSpeed * 12)
        }
        let turningAround = abs(cos(f.yaw)) < 0.5 || abs(Self.angleDifference(targetYaw, f.yaw)) > 1
        let sifting = f.species == .loach && f.feeding == nil && !f.burst.moving
        if !f.isChasingFood && turningAround && !f.species.isInvertebrate && !hoverTurn && !sifting {
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
        let sidestepping = bursting && f.burst.sidestepping
        if !f.species.isInvertebrate && slopeAlignment > 0 && !sidestepping {
            forwardTarget = max(forwardTarget, abs(desiredVY) * 0.5 * slopeAlignment)
        }
        // A sidestep starts nearly across the bed and arcs forward as it goes.
        if sidestepping { forwardTarget = min(forwardTarget, f.species.cruiseSpeed * (0.25 + 0.5 * min(1, f.burst.elapsed / 0.6))) }
        // A fish that spots food behind it brakes hard instead of coasting away.
        let braking = f.isChasingFood && alignment < 0 && !mostlyVertical ? 1 - exp(-movement * 12) : response
        f.forwardSpeed += (forwardTarget - f.forwardSpeed) * max(response, braking)
        var vy = f.vy + (desiredVY - f.vy) * response
        if !f.isChasingFood && !f.species.isInvertebrate && !sidestepping {
            // A fish climbs or dives along a gentle slope, never straight up like a lift.
            let climb = max(f.forwardSpeed * 0.6, f.species.cruiseSpeed * 0.15)
            vy = max(-climb, min(climb, vy))
        }
        if bursting {
            // A dart runs along the bed; moving farther back or nearer is slower going.
            let limit = f.species.cruiseSpeed
            vy = max(-limit, min(limit, vy))
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
        if f.species.isBottomDweller {
            // On the sand, farther away is higher up the receding bed.
            f.y += f.forwardSpeed * sin(f.yaw) * movement * Self.bedTravel
        } else {
            f.depth -= f.forwardSpeed * sin(f.yaw) * movement * Self.depthTravel
            // Drift back to the usual depth only while side-on, so it never cancels a turn's travel.
            f.depth += (f.homeDepth - f.depth) * (1 - exp(-movement * 0.4 * cos(f.yaw) * cos(f.yaw)))
            f.depth = f.depth.clamped(to: FishState.depthRange)
        }

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
