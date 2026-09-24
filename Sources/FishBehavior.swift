import Foundation
import CoreGraphics

/// A rectangle in normalized scene coordinates (0...1 on both axes, origin at bottom left).
struct SwimRegion {
    var left: Double, right: Double, bottom: Double, top: Double

    var width: Double { right - left }
    var height: Double { top - bottom }
    var center: (x: Double, y: Double) { ((left + right) / 2, (bottom + top) / 2) }

    func constrain(x: Double, y: Double) -> (Double, Double) {
        (min(right, max(left, x)), min(top, max(bottom, y)))
    }

    /// The overlap of two regions. When they do not overlap, collapses onto the
    /// closest point of `visible` so fish never leave the screen.
    func intersecting(_ visible: SwimRegion) -> SwimRegion {
        let x0 = max(left, visible.left), x1 = min(right, visible.right)
        let y0 = max(bottom, visible.bottom), y1 = min(top, visible.top)
        let fallbackX = min(visible.right, max(visible.left, center.x))
        let fallbackY = min(visible.top, max(visible.bottom, center.y))
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

    func point(x: Double, y: Double) -> CGPoint {
        CGPoint(x: imageRect.minX + x * imageRect.width, y: imageRect.minY + y * imageRect.height)
    }
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

/// Fish live in a shallow 3D tank: `x`/`y` are screen coordinates and `depth` is the
/// scale towards the viewer (larger is closer). `yaw` rotates the body about the
/// vertical axis: 0 faces right, π faces left, π/2 faces away from the viewer.
struct FishState: Identifiable {
    /// Depth band shared with particles, so far food passes behind every fish and near food in front.
    static let depthRange = 0.70...1.15

    var id: Int
    var species: FishSpecies
    var x: Double, y: Double, vx: Double, vy: Double
    var depth: Double
    /// The depth this individual drifts back to after a turn carries it nearer or farther.
    var homeDepth: Double
    var yaw: Double
    var yawVelocity = 0.0
    /// Speed along the body axis. Screen travel is its projection, so a fish never moves tail-first.
    var forwardSpeed = 0.0
    var facingRight: Bool
    /// How long an opposite horizontal intent has persisted, in movement units.
    var reversalUrge = 0.0
    /// The committed direction (+1 or -1) of a large turn in progress, or 0.
    var turnDirection = 0.0
    /// Direction of the last completed large turn, and movement since it ended.
    var lastTurnDirection = 0.0
    var sinceLastTurn = Double.infinity
    var finPhase = 0.0
    var stroke = FishStroke(seed: 1)
    var navigation = FishNavigation(seed: 1, heading: 0)
    /// Chance for moods, food reactions, and dispersal; separate from navigation and strokes.
    var dice = Dice(seed: 1)
    var personality = Personality.typical
    var pitch = 0.0
    var activity = 1.0
    var mood: FishMood = .cruise
    var moodRemaining = 6.0
    var appetite = 1.0
    var feeding: FeedingResponse?
    var feedingCooldown = 0.0
    var shrimpBehavior = ShrimpBehavior(seed: 1)
    var crabGait = CrabGait(seed: 1)

    init(id: Int, species: FishSpecies, x: Double, y: Double, depth: Double, facingRight: Bool, finPhase: Double, moodRemaining: Double) {
        self.id = id
        self.species = species
        self.x = x; self.y = y
        self.depth = depth; self.homeDepth = depth
        self.facingRight = facingRight
        self.forwardSpeed = species.cruiseSpeed
        self.vx = facingRight || species == .crab ? species.cruiseSpeed : -species.cruiseSpeed
        self.vy = 0
        self.yaw = species == .crab || facingRight ? 0 : .pi
        self.finPhase = finPhase
        self.moodRemaining = moodRemaining
    }

    /// A gourami or betta resting in mid-water, which turns on its fins rather than its body.
    var isHovering: Bool { species.isSlowGlider && mood == .hover && !isChasingFood }

    /// Going for food: noticing, approaching, or nibbling. A fish leaving after a meal
    /// swims like a wanderer again, so it glides away instead of pivoting on the spot.
    var isChasingFood: Bool {
        guard let phase = feeding?.phase else { return false }
        return phase != .leaving
    }

    var spineCurve: SIMD4<Float> {
        species.isInvertebrate ? .zero : stroke.spineCurve(phase: finPhase, species: species)
    }

    /// Fish keep a modest nose-up/down attitude. Rest and yaw turns level the body.
    /// A fish rising to food or diving for it may tip further, like a real fish striking upward.
    static func pitchTarget(species: FishSpecies, vx: Double, vy: Double, yawRate: Double, chasing: Bool = false) -> Double {
        guard !species.isInvertebrate else { return 0 }
        let limit = species.isBottomDweller ? 0.08 : (chasing ? 0.45 : 0.22)
        let moving = min(1, hypot(vx, vy) / 0.006)
        let turning = 1 / (1 + abs(yawRate) * 2.5)
        return max(-limit, min(limit, atan2(vy * 0.42, max(0.008, abs(vx))))) * moving * turning
    }
}

/// A lasting temperament drawn once at birth, so individuals of one species differ the way
/// real fish do: some swim a little faster, change their minds more often, or keep closer company.
struct Personality {
    /// Multiplies swimming speed.
    var boldness: Double
    /// Multiplies how often a fish picks a new intention.
    var restlessness: Double
    /// Typical pull toward others of the same species.
    var sociability: Double

    static let typical = Personality(boldness: 1, restlessness: 1, sociability: 0.18)

    init(boldness: Double, restlessness: Double, sociability: Double) {
        self.boldness = boldness; self.restlessness = restlessness; self.sociability = sociability
    }

    init(dice: inout Dice) {
        boldness = dice.logNormal(median: 1, spread: 0.12).clamped(to: 0.78...1.28)
        restlessness = dice.logNormal(median: 1, spread: 0.3).clamped(to: 0.5...2)
        sociability = dice.normal(mean: 0.18, deviation: 0.07).clamped(to: 0.02...0.35)
    }
}

enum ShrimpPhase: String, CaseIterable { case grazing, drifting, seekingCover, hidden, emerging }

/// Each shrimp alternates open exploration with a refuge near a planted edge. On the sand it
/// walks in short leg-steps with pauses to pick at food, swims only when drifting up into
/// the water, and flicks its tail to dart backward when a large fish comes close.
struct ShrimpBehavior {
    /// One tail flip, in movement units. Real flips last a few hundredths of a second; this
    /// is slowed just enough to be seen, and an escape is a burst of one to three flips.
    static let flipDuration = 0.12
    /// Free sand a sideways dart needs, in scene widths.
    static let dartLength = 0.035

    private var dice: Dice
    private(set) var phase: ShrimpPhase = .grazing
    private(set) var remaining: Double
    private(set) var target = SIMD2<Double>(0.5, 0.1)
    private(set) var concealment = 0.0
    private(set) var coverOnLeft = false
    /// Legs are moving in the current step; otherwise the shrimp is standing and picking.
    private(set) var stepping = false
    private var stepRemaining = 0.0
    private(set) var escapeRemaining = 0.0
    private(set) var escapeDuration = 0.0
    /// Horizontal direction of the current escape: +1 right, -1 left, 0 straight up.
    private(set) var escapeDirection = 1.0
    private var escapeCooldown = 0.0
    private(set) var escapes = 0

    init(seed: UInt64) {
        dice = Dice(seed: seed)
        remaining = dice.value(3...11)
        stepRemaining = dice.exponential(mean: 0.4)
    }

    var holdsPosition: Bool { phase == .hidden || phase == .emerging }
    var isEscaping: Bool { escapeRemaining > 0 }

    var activity: Double {
        switch phase {
        case .grazing: return stepping ? 0.6 : 0.0
        case .drifting: return 1.25
        case .seekingCover: return stepping ? 1.3 : 0.15
        case .hidden, .emerging: return 0.01
        }
    }

    /// Top of the grazing band within the shrimp's region.
    static func bedTop(of region: SwimRegion) -> Double { region.bottom + region.height * 0.46 }

    /// A predator came close on the side given by `threatDirection` (+1 right, -1 left).
    /// `room` is the free sand on each side. Returns true if the shrimp darts away; with no
    /// room on the far side it shoots straight up off the bed instead of into the edge.
    mutating func startle(threatDirection: Double, room: (left: Double, right: Double)) -> Bool {
        guard !holdsPosition, !isEscaping, escapeCooldown <= 0 else { return false }
        // Mostly bursts of two, sometimes one or three.
        let flips = [1, 1, 1, 2, 2, 2, 2, 2, 3, 3][Int(dice.next() * 10)]
        escapeDuration = Double(flips) * Self.flipDuration
        escapeRemaining = escapeDuration
        let away: Double = threatDirection >= 0 ? -1 : 1
        escapeDirection = (away < 0 ? room.left : room.right) > Self.dartLength ? away : 0
        escapeCooldown = dice.value(3...8)
        escapes += 1
        return true
    }

    mutating func advance(delta: Double, x: Double, y: Double, region: SwimRegion, feeding: Bool) {
        let bedTop = Self.bedTop(of: region)
        escapeCooldown -= delta
        if isEscaping {
            escapeRemaining -= delta
            if !isEscaping {
                // Freeze for a moment after the dart, as shrimp do.
                stepping = false
                stepRemaining = dice.exponential(mean: 0.8).clamped(to: 0.3...3)
            }
            return
        }
        // A rare spontaneous flick, even with nothing nearby.
        if !holdsPosition && !feeding && dice.chance(delta * 0.01) {
            _ = startle(threatDirection: dice.sign(), room: (x - region.left, region.right - x))
            return
        }
        advanceSteps(delta)
        if feeding {
            if phase != .grazing { phase = .grazing; remaining = dice.value(5...12) }
            concealment = max(0, concealment - delta * 0.65)
            return
        }
        remaining -= delta
        if phase == .seekingCover && hypot(x - target.x, (y - target.y) * 0.65) < 0.014 {
            phase = .hidden
            remaining = dice.value(3...9)
        } else if remaining <= 0 {
            switch phase {
            case .hidden:
                phase = .emerging
                remaining = 2.2
            case .grazing where dice.chance(0.55), .emerging:
                phase = .drifting
                remaining = dice.value(5...12)
                let inset = region.width * 0.18
                target = SIMD2(dice.value((region.left + inset)...(region.right - inset)), dice.value(bedTop...region.top))
            case .grazing, .drifting:
                phase = .seekingCover
                remaining = dice.value(6...15)
                coverOnLeft = dice.chance(0.5)
                // Each shrimp picks its own nook along the refuge edge.
                target = SIMD2(coverOnLeft ? region.left + 0.012 + dice.value(0...0.03) : region.right - 0.012 - dice.value(0...0.03),
                               bedTop - 0.006 - dice.value(0...0.015))
                (target.x, target.y) = region.constrain(x: target.x, y: target.y)
            case .seekingCover:
                phase = .grazing
                remaining = dice.value(4...10)
            }
        }
        concealment = max(0, min(1, concealment + delta * (phase == .hidden ? 0.6 : -0.65)))
    }

    /// Stop-and-go walking: short steps separated by random pauses, longer while grazing.
    private mutating func advanceSteps(_ delta: Double) {
        stepRemaining -= delta
        guard stepRemaining <= 0 else { return }
        stepping.toggle()
        if stepping {
            stepRemaining = dice.exponential(mean: 0.2).clamped(to: 0.06...0.6)
        } else {
            stepRemaining = dice.exponential(mean: phase == .grazing ? 0.6 : 0.12).clamped(to: 0.05...3)
        }
    }
}

/// Crabs walk sideways in short bursts, stopping often to pick at the sand. Most bursts
/// continue the same way; some reverse, and now and then a crab shuffles forward or back.
struct CrabGait {
    private var dice: Dice
    private(set) var walking = false
    private(set) var remaining: Double
    /// Direction of travel on the sand, in radians: 0 is right, π is left.
    private(set) var direction: Double
    /// Speed of the current burst, relative to cruise speed.
    private(set) var pace = 1.0
    private(set) var bouts = 0

    init(seed: UInt64) {
        dice = Dice(seed: seed)
        remaining = dice.exponential(mean: 1.0)
        direction = dice.chance(0.5) ? 0 : .pi
    }

    /// Something is in the way: stop, and set off the other way on the next burst.
    mutating func bumped() {
        guard walking else { return }
        walking = false
        remaining = dice.exponential(mean: 0.5).clamped(to: 0.15...2)
        direction = .pi - direction
    }

    var velocityFactor: (x: Double, y: Double) {
        walking ? (cos(direction) * pace, sin(direction) * pace) : (0, 0)
    }

    mutating func advance(delta: Double, x: Double, y: Double, region: SwimRegion) {
        guard delta > 0 else { return }
        remaining -= delta
        // At the edge of the sand, turn back the other way.
        let margin = min(0.03, region.width * 0.15)
        if (x < region.left + margin && cos(direction) < 0) || (x > region.right - margin && cos(direction) > 0) {
            direction = .pi - direction
        }
        if (y < region.bottom + 0.004 && sin(direction) < 0) || (y > region.top - 0.004 && sin(direction) > 0) {
            direction = -direction
        }
        guard remaining <= 0 else { return }
        if walking {
            walking = false
            remaining = dice.exponential(mean: 0.9).clamped(to: 0.2...6)
            return
        }
        walking = true
        bouts += 1
        // Quick scuttles of about half a body length, rather than a slow stroll.
        remaining = dice.exponential(mean: 0.6).clamped(to: 0.15...2)
        pace = dice.logNormal(median: 3, spread: 0.25).clamped(to: 1.5...4.5)
        if dice.chance(0.15) {
            // Walking forward or back is awkward for a crab: rarer and slower.
            direction = dice.sign() * .pi / 2 + dice.normal(deviation: 0.25)
            pace *= 0.5
        } else {
            let side = cos(direction) >= 0 ? 0.0 : Double.pi
            direction = (dice.chance(0.65) ? side : .pi - side) + dice.normal(deviation: 0.18)
        }
    }
}

/// A fish chooses intentions at random moments, like a real animal: most waits are short
/// and a few long (exponential), most course changes are small with occasional wide turns
/// and reversals (normal), and between decisions its heading meanders in a slow, correlated
/// drift (an Ornstein–Uhlenbeck process), so paths curve instead of running in straight lines.
struct FishNavigation {
    /// Turning speed limits in radians per unit of movement. At the default swimming
    /// speed a relaxed U-turn takes roughly one and a half to three seconds.
    static let turnLimits = 2.2...5.0
    /// Mean movement between decisions for a fish of typical restlessness.
    static let meanDecisionInterval = 2.2
    static let reversalChance = 0.09
    /// Typical course change in radians (about 30°).
    static let turnDeviation = 0.55
    /// How quickly the meander returns to straight, and how strongly it wanders.
    static let meanderReversion = 1.5
    static let meanderStrength = 0.9

    private var dice: Dice
    private let restlessness: Double
    private let sociability: Double
    /// Scales the vertical part of every heading; bottom dwellers on a shallow bed keep
    /// their courses nearly level instead of repeatedly bouncing off its top and bottom.
    private let flatness: Double
    private(set) var heading: Double
    private(set) var remaining: Double
    private(set) var speedFactor = 1.0
    private(set) var turnLimit = 3.0
    /// A slight three-quarter view held while cruising, so the school never looks flat.
    private(set) var viewAngle = 0.0
    private(set) var shoalAffinity = 0.15
    /// Current rate of heading drift between decisions, in radians per movement unit.
    private(set) var meander = 0.0
    private(set) var decisions = 0
    private(set) var lastTurn = 0.0

    init(seed: UInt64, heading: Double, personality: Personality = .typical, flatness: Double = 1) {
        dice = Dice(seed: seed)
        self.flatness = flatness
        restlessness = personality.restlessness
        sociability = personality.sociability
        self.heading = heading
        remaining = dice.exponential(mean: 1.2)
        speedFactor = dice.logNormal(median: 1, spread: 0.2).clamped(to: 0.6...1.4)
        turnLimit = dice.value(Self.turnLimits)
        viewAngle = dice.normal(deviation: 0.2).clamped(to: -0.32...0.32)
        shoalAffinity = sociability
    }

    mutating func advance(delta: Double, x: Double, y: Double, region: SwimRegion, resting: Bool) {
        guard delta > 0 else { return }
        remaining -= delta
        guard !resting else { return }
        meander += -meander * Self.meanderReversion * delta + Self.meanderStrength * sqrt(delta) * dice.normal(deviation: 1)
        heading += meander * delta
        let marginX = min(0.055, region.width * 0.18)
        let marginY = min(0.04, region.height * 0.22)
        let approachingEdge = (x < region.left + marginX && cos(heading) < -0.2)
            || (x > region.right - marginX && cos(heading) > 0.2)
            || (y < region.bottom + marginY && sin(heading) < -0.2)
            || (y > region.top - marginY && sin(heading) > 0.2)
        guard remaining <= 0 || approachingEdge else {
            heading = atan2(sin(heading), cos(heading))
            return
        }
        let old = heading
        if approachingEdge {
            // Head back toward open water, loosely aimed at the region's center.
            heading = atan2((region.center.y - y) * 0.65, region.center.x - x) + dice.normal(deviation: 0.2)
            meander = 0
        } else if dice.chance(Self.reversalChance) {
            heading += (.pi + dice.normal(deviation: 0.2)) * dice.sign()
        } else {
            heading += dice.normal(deviation: Self.turnDeviation).clamped(to: -2.3...2.3)
        }
        heading = atan2(sin(heading) * flatness, cos(heading))
        lastTurn = AquariumSimulation.angleDifference(heading, old)
        decisions += 1
        remaining = (dice.exponential(mean: Self.meanDecisionInterval) / restlessness).clamped(to: 0.4...10)
        speedFactor = dice.logNormal(median: 1, spread: 0.28).clamped(to: 0.45...1.6)
        turnLimit = dice.value(Self.turnLimits)
        viewAngle = dice.normal(deviation: 0.28).clamped(to: -0.52...0.52)
        // Sometimes a fish strikes out alone for a while.
        shoalAffinity = dice.chance(0.3) ? 0 : dice.normal(mean: sociability, deviation: 0.05).clamped(to: 0...0.35)
    }
}

/// Independent, smoothly changing motor rhythms; this stream never changes navigation or feeding decisions.
struct FishStroke {
    private var dice: Dice
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
    /// Head-to-tail angle of the body's C-bend while turning, in radians.
    private(set) var bend = 0.0
    private var bendVelocity = 0.0
    /// Stiffness and damping of the bend. Underdamped, so after the body curves into a turn
    /// the tail flips back past straight once before it settles (the two stages of a routine turn).
    static let bendStiffness = 90.0
    static let bendDamping = 2 * 0.45 * 90.0.squareRoot()

    init(seed: UInt64) {
        dice = Dice(seed: seed)
        pectoralPhase = dice.value(0...(2 * .pi))
        dorsalPhase = dice.value(0...(2 * .pi))
        remaining = dice.value(0.2...1.4)
        cadence = dice.value(0.85...1.15)
        cadenceTarget = cadence
    }

    /// The second stage of a turn: one sweep of the tail carries the body back past straight.
    /// `turn` is the direction of the finished turn (+1 or -1).
    mutating func sweepTailBack(turn: Double, species: FishSpecies) {
        // Nimble small fish snap the tail back hardest.
        bendVelocity -= turn * Self.tailSweep * species.bodyFlexibility * species.turnAgility
    }
    /// Bend speed of the tail sweep, in radians per movement unit.
    static let tailSweep = 6.0

    /// Polynomial coefficients of the lateral spine offset consumed by `FishRendering.spine`.
    func spineCurve(phase: Double, species: FishSpecies) -> SIMD4<Float> {
        let power = amplitude * (species == .loach ? 0.25 : 0.18)
        let wave = sin(phase), follow = sin(phase - 1.4)
        return SIMD4(Float(-bend * 0.6 + power * wave),
                     Float(power * (follow - wave) * 1.6),
                     Float(-power * follow * 0.65), 0)
    }

    /// `hovering`: the fish is rotating in place on its pectoral fins, with a nearly straight body.
    mutating func advance(delta: Double, species: FishSpecies, speed: Double, acceleration: Double, turnRate: Double,
                          turnAcceleration: Double = 0, hovering: Bool = false) {
        guard delta > 0 else { return }
        remaining -= delta
        if remaining <= 0 {
            coasting = !coasting && dice.next() < (species == .loach ? 0.20 : 0.48)
            remaining = coasting ? dice.value(0.35...1.15) : dice.value(0.65...2.6)
            cadenceTarget = dice.value(0.78...1.22)
            strengthTarget = coasting ? dice.value(0.12...0.28) : dice.value(0.75...1.15)
            finTarget = dice.value(0.65...1.25)
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
        // Stage one: as a turn speeds up, the head swings into it and the body curves into a C,
        // more deeply the faster the turn. Stage two: as the turn slows, the tail sweeps back
        // past straight once and the body settles. Larger fish curve less.
        let flexibility = species.bodyFlexibility
        let swing = (turnAcceleration * 0.07).clamped(to: -0.8...0.8)
        let bendTarget = ((turnRate * 0.3 + swing) * flexibility * (hovering ? 0.15 : 1)).clamped(to: -1.4 * flexibility...1.4 * flexibility)
        bendVelocity += (Self.bendStiffness * (bendTarget - bend) - Self.bendDamping * bendVelocity) * delta
        bend += bendVelocity * delta
    }
}
