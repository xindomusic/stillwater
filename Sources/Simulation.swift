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
    /// How far each foot sweeps back while planted, in photo texture units; generated into
    /// the crab shader by `FishRendering` so feet stay fixed to the sand.
    static let crabStride = 0.2
    /// A stride toward or away from the viewer is drawn foreshortened to this share of its length.
    static let crabVerticalStride = 0.5
    /// Share of each step cycle a foot spends planted (stance), generated into the shader.
    static let crabStance = 0.6
    /// Leg-cycle radians per movement unit for a walking shrimp.
    static let shrimpStepRate = 18.0
    /// How far a shrimp's planted foot sweeps over half a step cycle, in photo units.
    static let shrimpStance = 0.04
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
    var food: [FoodPellet] = []
    var pendingFood: [FoodPellet] = []
    private(set) var bubbleField: BubbleField
    var sand: SandField
    var bubbles: [BubbleState] { bubbleField.bubbles }
    var mealsEaten = 0
    private(set) var time = 0.0
    var visibleRegion = SwimRegion(left: 0, right: 1, bottom: 0, top: 1)

    let entitySeed: UInt64
    var dice: Dice
    private var nextID = 0
    var nextFoodID = 0
    private var bubbleRegion: SwimRegion?
    var lastDropX: Double?
    private var theme: AquariumTheme?
    var neighbors: [Neighbor] = []

    struct Neighbor {
        var id: Int, species: FishSpecies
        var x: Double, y: Double, vx: Double, vy: Double
        var size: Double
        var depth: Double
        /// A loach lying at rest (and how it lies), and a loach setting off on a bout, or darting
        /// off, this very update.
        var resting = false, settingOff = false, dartingOff = false
        var restYaw = 0.0, restBend = 0.0
    }

    /// Where a fish wants to go this frame and how urgently.
    struct SteeringGoal {
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
                if fish[i].species == .shrimp {
                    fish[i].shrimpBehavior = ShrimpBehavior(seed: entitySeed ^ (UInt64(fish[i].id) &* 0x9E3779B97F4A7C15) ^ 0x5A11 ^ 0x7E3E)
                }
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
        switch species {
        case .shrimp: resident.speciesBehavior = .shrimp(ShrimpBehavior(seed: personalSeed ^ 0x5A11))
        case .crab: resident.speciesBehavior = .crab(CrabGait(seed: personalSeed ^ 0xC2AB))
        case .loach: resident.speciesBehavior = .loach(BurstRhythm(seed: personalSeed ^ 0xB0257))
        default: break
        }
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
                                        size: $0.species.bodySize * $0.depth, depth: $0.depth,
                                        resting: $0.species == .loach && $0.burst.regime == .rest && $0.feeding == nil,
                                        settingOff: $0.species == .loach && $0.burst.justSetOff,
                                        dartingOff: $0.species == .loach && $0.burst.justSetOff && $0.burst.pace > 2,
                                        restYaw: $0.burst.restYaw, restBend: $0.burst.restBend) }
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
        if f.species == .loach && f.feeding == nil { chooseRestSpot(&f, goal: &goal, home: home, theme: theme) }
        let previousBouts = f.crabGait.bouts, wasStepping = f.shrimpBehavior.stepping
        if f.species == .shrimp {
            steerShrimp(&f, goal: &goal, movement: movement, home: home, theme: theme)
            // Standing to graze, its claws pick at the surface about three and a half times a
            // second at the default swimming speed.
            let b = f.shrimpBehavior
            let picking = (b.phase == .grazing && !b.stepping && !b.isEscaping) || f.feeding != nil
            // Each shrimp picks to its own rhythm, a little faster or slower than the next.
            let pickRate = 6 + 2 * (Double(f.id) * 0.618).truncatingRemainder(dividingBy: 1)
            f.shrimpBehavior.pickPhase = (f.shrimpBehavior.pickPhase + movement * 2 * .pi * pickRate).truncatingRemainder(dividingBy: 2 * .pi)
            f.shrimpBehavior.pickEnvelope += ((picking ? 1 : 0) - f.shrimpBehavior.pickEnvelope) * (1 - exp(-movement * 30))
        }
        if f.species == .loach {
            f.burst.othersResting = neighbors.filter { $0.id != f.id && $0.species == .loach && $0.resting }.count
            f.burst.othersMoving = neighbors.contains { $0.id != f.id && $0.species == .loach && !$0.resting }
            // When the whole group has lain still a while, one of them gets up again.
            if f.burst.regime == .rest && f.burst.restSpot == nil && !f.burst.othersMoving && f.dice.chance(movement * 0.08) { f.burst.wake() }
            f.burst.advance(delta: movement)
            // A loach that needs to turn around sets off and swims round rather than spinning in
            // place, and keeps swimming until the turn is done.
            let turnLeft = abs(Self.angleDifference(f.facingRight ? 0 : .pi, f.yaw))
            if f.feeding == nil {
                if !f.burst.moving && turnLeft > 1 { f.burst.startBurst() }
                // A turn-around swims back into the lane it came from; only a dart straight
                // ahead is checked against the neighbours in that lane.
                let wasSidestepping = f.burst.sidestepping
                if turnLeft > 0.5 && !f.burst.sidestepping { f.burst.hold(0.15); f.burst.calm(to: max(f.burst.turnPace, 1.1)); f.burst.hurry(to: f.burst.turnPace) } else { keepDartLaneClear(&f, home: home, movement: movement) }
                // A sidestep ends where it ends, without a lurch forward as the drive dies away.
                if wasSidestepping && !f.burst.moving { f.activity = min(f.activity, 0.4) }
                if f.burst.moving && !f.burst.justSetOff { f.burst.parkedFor = 0 } else { f.burst.parkedFor += movement }
                // A foraging loach that has paused a while often sets off too when a neighbour does.
                let length = f.species.bodyLength * f.depth
                if !f.burst.moving && f.burst.regime == .forage && f.burst.parkedFor > 1,
                   neighbors.contains(where: { $0.settingOff && $0.id != f.id && hypot($0.x - f.x, $0.y - f.y) < length * 2 }),
                   f.dice.chance(0.25) {
                    f.burst.startBurst()
                    keepDartLaneClear(&f, home: home, movement: movement)
                }
                // A dart close by often sets it darting too.
                if f.burst.regime == .forage && f.feeding == nil,
                   neighbors.contains(where: { $0.dartingOff && $0.id != f.id && hypot($0.x - f.x, $0.y - f.y) < length * 2 }),
                   f.dice.chance(0.4) {
                    f.burst.dartAway()
                    keepDartLaneClear(&f, home: home, movement: movement)
                }
            }
            f.burst.siftClock += movement
            // Foraging, the head stays down in the sand, even while it slithers slowly on; resting,
            // the chin just lies on the sand; roaming or darting, the head is up.
            var target: Double
            if f.feeding != nil { target = 0 }
            else if f.burst.regime == .rest { target = 0.35 }
            else if !f.burst.moving { target = 1 }
            else if f.burst.regime != .roam && f.burst.pace < 2 { target = 0.6 }
            else { target = 0 }
            // Once raised or lowered, the head holds a moment rather than flicking up and down.
            f.burst.headHold -= movement
            if target != f.burst.headTarget {
                if f.burst.headHold <= 0 || f.feeding != nil || f.burst.pace > 2 { f.burst.headTarget = target; f.burst.headHold = 0.8 } else { target = f.burst.headTarget }
            }
            f.burst.siftEnvelope += (target - f.burst.siftEnvelope) * (1 - exp(-dt * (target > f.burst.siftEnvelope ? 4 : 25)))
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
        if f.species == .shrimp && !f.shrimpBehavior.isEscaping { stepShrimpLegs(&f, dx: f.x - startX, dy: f.y - startY) }
        if f.species == .crab { stepCrabLegs(&f, dx: f.x - startX, dy: f.y - startY, dt: dt, movement: movement) }
        eatIfReached(&f, targetFood: goal.targetFood)
        stirSand(f, previousBouts: previousBouts, wasStepping: wasStepping, movement: movement)
    }

    /// A shrimp's legs step exactly as far as it walks: each planted foot sweeps back about 0.04
    /// photo units over half a cycle (FishRendering's shrimp legs at full swing).
    private func stepShrimpLegs(_ f: inout FishState, dx: Double, dy: Double) {
        let photoUnit = f.species.sceneWidthPerPhotoUnit * f.depth
        let walked = hypot(dx, dy / TankScale.aspect)
        f.finPhase += min(.pi * 0.9, walked / photoUnit / Self.shrimpStance * .pi)
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
            if ax * f.crabGait.legAxisX + ay * f.crabGait.legAxisY < 0 { ax = -ax; ay = -ay }
            let turn = 1 - exp(-movement * 8)
            let nx = f.crabGait.legAxisX + (ax - f.crabGait.legAxisX) * turn, ny = f.crabGait.legAxisY + (ay - f.crabGait.legAxisY) * turn
            let length = max(1e-6, hypot(nx, ny))
            f.crabGait.legAxisX = nx / length; f.crabGait.legAxisY = ny / length
        }
        // Vertical travel is drawn foreshortened, so the legs cycle further for it.
        let along = tx * f.crabGait.legAxisX + ty * f.crabGait.legAxisY / Self.crabVerticalStride
        // Capped below half a cycle per update, so even at the fastest settings the legs never strobe.
        let step = along / (Self.crabStride / Self.crabStance) * 2 * .pi
        f.finPhase += step.clamped(to: -0.9 * .pi...0.9 * .pi)
        // Standing still, lifted feet come down within about a tenth of a second of real time.
        let speed = travel / max(movement, 1e-6) * photoUnit
        let standing = speed < f.species.cruiseSpeed * 0.2
        f.crabGait.legSettle += ((standing ? 1 : 0) - f.crabGait.legSettle) * (1 - exp(-dt * (standing ? 15 : 30)))
    }

    /// Residents that work the bed kick up a little sand as they go.
    private mutating func stirSand(_ f: FishState, previousBouts: Int, wasStepping: Bool, movement: Double) {
        let floor = Self.sandContact(of: f)
        switch f.species {
        case .loach:
            // A foraging loach pauses to nose into the sand, throwing up a puff each time.
            let sifting = f.feeding == nil && f.mood == .forage && f.forwardSpeed < f.species.cruiseSpeed * 0.3 && f.burst.regime != .rest
            let crawling = f.feeding == nil && f.burst.moving && f.burst.pace < 0.45 && f.burst.regime == .forage
            if (sifting && sand.chance(movement * 0.5)) || (crawling && sand.chance(movement * 0.6)) {
                let snout = f.x + cos(f.yaw) * f.species.bodyLength * 0.45
                sand.puff(x: snout, floor: floor, depth: f.depth, strength: f.burst.moving ? 0.35 : 0.6)
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
        if f.species == .loach {
            // A loach's rests and forays are set by its own rhythm (BurstRhythm.regime).
            f.mood = .forage
            f.moodRemaining = 20
            return
        }
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

    private func steerShrimp(_ f: inout FishState, goal: inout SteeringGoal, movement: Double, home: SwimRegion, theme: AquariumTheme) {
        let threat = nearestThreat(to: f)
        if let threat {
            // A tail flip drives the body backward along the way it actually points, even mid-turn.
            _ = f.shrimpBehavior.startle(threatDirection: threat.x >= f.x ? 1 : -1, facingRight: cos(f.yaw) >= 0, room: (f.x - home.left, home.right - f.x))
        }
        f.shrimpBehavior.advance(delta: movement, x: f.x, y: f.y, facingRight: cos(f.yaw) >= 0, region: home,
            refuges: Self.shrimpRefuges(theme: theme), feeding: f.feeding != nil, threatened: threat != nil)
        guard f.feeding == nil else { return }
        switch f.shrimpBehavior.phase {
        case .grazing: goal.y = min(goal.y, ShrimpBehavior.bedTop(of: home))
        case .seekingCover:
            // Up or down the bed only clear of the rock: first to its base line beside it, then
            // sideways in behind it.
            if let rock = f.shrimpBehavior.refuge, f.y < rock.y - 0.002 || f.y > rock.y + 0.008,
               let approach = f.shrimpBehavior.approach(from: f.x) {
                goal.x = approach.x; goal.y = approach.y
            } else {
                goal.x = f.shrimpBehavior.target.x; goal.y = f.shrimpBehavior.target.y
            }
        case .drifting: goal.x = f.shrimpBehavior.target.x; goal.y = f.shrimpBehavior.target.y
        case .hidden: goal.x = f.x; goal.y = f.y
        case .emerging:
            let exit = f.shrimpBehavior.exit ?? SIMD2(f.x, f.y)
            goal.x = exit.x; goal.y = exit.y
        }
    }

    /// The highest a shrimp walking on the sand stands: the grazing band, or the nook it heads for.
    static func shrimpFloor(_ f: FishState, theme: AquariumTheme) -> Double {
        let bedTop = ShrimpBehavior.bedTop(of: region(for: .shrimp, theme: theme))
        guard let rock = f.shrimpBehavior.refuge,
              f.shrimpBehavior.phase == .seekingCover || f.shrimpBehavior.phase == .emerging else { return bedTop }
        return max(bedTop, rock.y + 0.004)
    }

    /// Rocks beside each scene's sand bed that shrimp walk behind to hide, read off the scene's
    /// `-crystal` artwork: each rock's side edge where it meets the sand.
    static func shrimpRefuges(theme: AquariumTheme) -> [ShrimpRefuge] {
        switch theme {
        // Each rock is a dome standing on the sand: `center` on its base line, `radii` its half-width
        // and height. A shrimp walks behind it just above the base line (`y`).
        case .river: return [
            ShrimpRefuge(edge: 0.478, y: 0.178, side: 1, center: SIMD2(0.513, 0.168), radii: SIMD2(0.043, 0.085)),
            ShrimpRefuge(edge: 0.567, y: 0.146, side: 1, center: SIMD2(0.622, 0.136), radii: SIMD2(0.062, 0.082))]
        case .grove: return [
            ShrimpRefuge(edge: 0.557, y: 0.113, side: -1, center: SIMD2(0.538, 0.103), radii: SIMD2(0.021, 0.053)),
            ShrimpRefuge(edge: 0.756, y: 0.170, side: 1, center: SIMD2(0.772, 0.160), radii: SIMD2(0.018, 0.04))]
        case .spring: return [
            ShrimpRefuge(edge: 0.509, y: 0.123, side: 1, center: SIMD2(0.572, 0.113), radii: SIMD2(0.066, 0.147)),
            ShrimpRefuge(edge: 0.44, y: 0.153, side: 1, center: SIMD2(0.457, 0.143), radii: SIMD2(0.025, 0.047))]
        }
    }

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
            return f.burst.moving ? 8 * f.burst.pace * (0.55 + 0.45 * exp(-f.burst.elapsed / 0.45)) : 0
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
                let together = bothResting(f, other)
                guard abs(other.depth - f.depth) < Self.bedLayer || (Self.keepApartAtAnyDepth(f.species, other.species) && !together),
                      !holdsGround(f, against: other) else { continue }
                // Resting loaches lie close alongside one another, as kuhlis do.
                let reachX = (f.species.bedFootprint * f.depth + other.species.bedFootprint * other.depth) * 0.5
                    * (together ? 0.6 : Self.bedReachX(f.species, other.species, feeding: f.isChasingFood))
                let reachY = together ? 0.01 : Self.bedReachY(f.species, other.species)
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
                // A move to another lane is a forward swim turned well toward it, never a slide sideways.
                let speed = hypot(desiredVX, desiredVY)
                (desiredVX, desiredVY) = ((f.facingRight ? 1 : -1) * speed * cos(0.9), (f.burst.bearing > 0 ? 1 : -1) * speed * sin(0.9))
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
            responseRate = 20
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
        let unclamped = f.x
        (f.x, f.y) = goal.region.constrain(x: f.x, y: f.y)
        if f.species == .loach && f.x != unclamped {
            // Nose against the end of the bed: it stops driving rather than wriggling on the spot.
            f.forwardSpeed = min(f.forwardSpeed, f.species.cruiseSpeed * 0.3)
        }
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
            // Legs step with the distance walked (see `stepShrimpLegs`); a feeding shrimp picks.
            if f.feeding != nil { f.finPhase += movement * Self.shrimpStepRate * 0.3 }
        } else if f.species == .loach {
            // Anguilliform swimming: the body wave travels back a little faster than the fish moves
            // forward, about one and a half waves per body length, plus a slow ripple at rest.
            // A burst adds a quick beat of its own: a kuhli loach wriggles at two to three waves a second.
            let travelled = hypot(f.vx, f.vy) * movement / (f.species.bodyLength * f.depth)
            f.finPhase += travelled * 2 * .pi * 1.5 + movement * 0.35 + movement * 2 * .pi * 2 * min(1, f.activity / 5)
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
        let decay = 5.0
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
        f.vy = distance * TankScale.aspect * (direction == 0 ? 1 : 0.35) / movement
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
            ? (f.burst.bearing > 0 ? 0.9 : -0.9) * (f.facingRight ? 1 : -1) : 0
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
            turnLimit *= f.species == .shrimp ? Self.headOnHurry * 8 : Self.headOnHurry
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
            forwardTarget = min(max(forwardTarget, drive), f.species.cruiseSpeed * 20)
        }
        let turningAround = abs(cos(f.yaw)) < 0.5 || abs(Self.angleDifference(targetYaw, f.yaw)) > 1
        let sifting = f.species == .loach && f.feeding == nil && !f.burst.moving
        if f.species == .shrimp && turningAround {
            // Keep walking through the turn rather than spinning on the spot.
            forwardTarget = max(forwardTarget, f.species.cruiseSpeed * 0.3)
        }
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
        // A fish that spots food behind it brakes hard instead of coasting away.
        let braking = f.isChasingFood && alignment < 0 && !mostlyVertical ? 1 - exp(-movement * 12) : response
        f.forwardSpeed += (forwardTarget - f.forwardSpeed) * max(response, braking)
        var vy = f.vy + (desiredVY - f.vy) * response
        if !f.isChasingFood && !f.species.isInvertebrate && !sidestepping {
            // A fish climbs or dives along a gentle slope, never straight up like a lift.
            let climb = max(f.forwardSpeed * 0.6, f.species.cruiseSpeed * 0.15)
            vy = max(-climb, min(climb, vy))
        }
        if bursting || f.species == .loach {
            // A dart runs along the bed; moving farther back or nearer is slower going, and a loach
            // coasting out of a dart does not slide up or down the bed either.
            let limit = f.species.cruiseSpeed
            vy = max(-limit, min(limit, vy))
        }
        f.vy = vy
        if f.species == .shrimp, !f.shrimpBehavior.isEscaping, let theme,
           f.y > Self.region(for: .shrimp, theme: theme).top
            || (f.shrimpBehavior.phase != .drifting && !f.shrimpBehavior.holdsPosition && f.feeding == nil
                && f.y > Self.shrimpFloor(f, theme: theme) + 0.004) {
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
            // On the sand, farther away is higher up the receding bed. A quick dart runs along
            // the bed; up or down it, a loach goes no faster than a brisk swim.
            let upBed = f.forwardSpeed * sin(f.yaw)
            let darting = f.species == .loach && f.burst.moving && f.burst.pace > 2
            let limit = darting ? f.species.cruiseSpeed * 2.5 : Double.infinity
            f.y += max(-limit, min(limit, upBed)) * movement * Self.bedTravel
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
        // A shrimp turns round only while it is stepping, walking round a small arc.
        let shrimpStanding = f.species == .shrimp && !f.shrimpBehavior.stepping && !f.shrimpBehavior.isEscaping && f.feeding == nil
        // A standing shrimp keeps its wish to turn round for its next step, rather than forgetting it.
        if shrimpStanding && opposing && !midTurn { return }
        // A loach lying at rest does not turn round where it lies.
        // Nor does a darting loach turn straight round mid-dart.
        let loachLying = f.species == .loach && f.feeding == nil
            && ((f.burst.regime == .rest && f.burst.restSpot == nil) || (f.burst.moving && f.burst.pace > 2))
        guard opposing && !midTurn && !nibbling && !shrimpStanding && !loachLying else { f.reversalUrge = 0; return }
        f.reversalUrge += movement
        // A loach keeps to its heading along the sand far longer before it thinks of turning round.
        // A foraging loach works steadily along the sand rather than doubling back.
        let loachPatience = f.species == .loach ? (f.burst.regime == .forage ? 6.0 : 3.0) : 1.0
        let patience = f.isChasingFood ? Self.feedingReversalPatience : Self.reversalPatience * loachPatience
        if f.reversalUrge >= patience {
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

}
