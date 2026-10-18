import Foundation

// Life on the sand bed: lanes, resting spots, and keeping neighbours apart.
// Split out of Simulation.swift; members used here are internal rather than
// private so this extension can live in its own file (single-module app).
extension AquariumSimulation {
    /// Vertical separation of two bed residents on screen.
    static func bedGap(_ y: Double, _ depth: Double, _ otherY: Double, _ otherDepth: Double) -> Double { y - otherY }

    /// A crab and another bed resident: crabs never settle over a loach or shrimp, at any depth,
    /// because their splayed legs would seem to stand on it.
    static func crabAndLoach(_ a: FishSpecies, _ b: FishSpecies) -> Bool {
        a == .crab || b == .crab
    }

    /// Pairs that must never overlap on screen, whatever their depth: crabs with anyone, and
    /// loaches with each other, which would otherwise line up nose to tail and read as one fish.

    /// Pairs that must never overlap on screen, whatever their depth: crabs with anyone, and
    /// loaches with each other, which would otherwise line up nose to tail and read as one fish.
    static func keepApartAtAnyDepth(_ a: FishSpecies, _ b: FishSpecies) -> Bool {
        // Nor does a shrimp ever seem to stand on a loach's back.
        crabAndLoach(a, b) || (a == .loach && b == .loach) || Set([a, b]) == [.shrimp, .loach]
    }

    /// How far apart two bed residents must be up and down the screen: a crab's legs reach well
    /// above and below its shell.

    /// How far apart two bed residents must be up and down the screen: a crab's legs reach well
    /// above and below its shell.
    static func bedReachY(_ a: FishSpecies, _ b: FishSpecies) -> Double {
        crabAndLoach(a, b) ? 0.035 : 0.02
    }

    /// A crab heading for food with another crab already between it and the food, close by.

    /// A loach settling down to rest goes to lie at the foot of a nearby rock, or alongside another
    /// resting loach (kuhli loaches rest together), and crawls there before it settles.
    func chooseRestSpot(_ f: inout FishState, goal: inout SteeringGoal, home: SwimRegion, theme: AquariumTheme) {
        guard f.burst.regime == .rest else { f.burst.restSpot = nil; return }
        let length = f.species.bodyLength * f.depth
        if f.burst.justEnteredRest {
            f.burst.restSpot = nil
            let roll = f.dice.next()
            let rocks = Self.shrimpRefuges(theme: theme).map { rock in
                SIMD2(rock.edge - rock.side * length * 0.3, min(home.top - 0.005, rock.y - 0.01))
            }
            let nearestRock = rocks.min { hypot($0.x - f.x, $0.y - f.y) < hypot($1.x - f.x, $1.y - f.y) }
            // A resting loach that already has company draws others more, so groups form.
            func company(_ n: Neighbor) -> Int {
                neighbors.filter { $0.id != n.id && $0.resting && hypot($0.x - n.x, $0.y - n.y) < length * 1.5 }.count
            }
            let companion = neighbors.filter { $0.id != f.id && $0.resting && hypot($0.x - f.x, $0.y - f.y) < length * 8 }
                .min { hypot($0.x - f.x, $0.y - f.y) - Double(company($0)) * length < hypot($1.x - f.x, $1.y - f.y) - Double(company($1)) * length }
            f.burst.restCompanion = nil
            if roll < 0.7, let other = companion {
                // Alongside a resting loach, nearly level with it, a little farther back or nearer.
                let along = f.dice.sign() * f.dice.value(0...0.25) * length
                let beside = f.dice.sign() * f.dice.value(0.02...0.03)
                f.burst.restSpot = SIMD2(other.x + along, (other.y + beside).clamped(to: home.bottom...home.top))
                f.burst.restCompanion = other.id
            } else if roll < 0.9, let rock = nearestRock, hypot(rock.x - f.x, rock.y - f.y) < length * 3 {
                f.burst.restSpot = rock
            }
        }
        guard let spot = f.burst.restSpot else { return }
        if hypot(spot.x - f.x, (spot.y - f.y) * Self.verticalWeight) > length * 0.4 && f.burst.parkedFor < 3 {
            f.burst.crawl()
            goal.x = spot.x; goal.y = spot.y
        } else {
            // Arrived (or held up too long): lie down here, curled the way its companion lies.
            f.burst.restSpot = nil
            if let id = f.burst.restCompanion, let other = neighbors.first(where: { $0.id == id }) {
                // Lying at an angle across its companion, curled the other way.
                let sign: Double = other.restBend >= 0 ? -1 : 1
                f.burst.settleHere(yaw: other.restYaw + f.dice.sign() * f.dice.value(0.3...0.5),
                                   bend: sign * f.dice.value(0.2...0.6))
            } else {
                f.burst.settleHere()
            }
            f.burst.restCompanion = nil
        }
    }

    /// A loach never darts into a neighbour. Setting off with someone close ahead in its lane, it
    /// goes the other way if that lane is clear, or takes a short hop toward whichever side has
    /// more room; boxed in on both sides for long, it sidesteps to another lane. A neighbour
    /// moving into the lane during a dart ends the dart, and the loach coasts to a stop short of it.

    /// A loach never darts into a neighbour. Setting off with someone close ahead in its lane, it
    /// goes the other way if that lane is clear, or takes a short hop toward whichever side has
    /// more room; boxed in on both sides for long, it sidesteps to another lane. A neighbour
    /// moving into the lane during a dart ends the dart, and the loach coasts to a stop short of it.
    func keepDartLaneClear(_ f: inout FishState, home: SwimRegion, movement: Double) {
        guard f.burst.moving else { return }
        let ahead = f.facingRight ? 1.0 : -1.0
        let length = f.species.bodyLength * f.depth
        // The end of the bed counts as an obstacle too.
        let toWall = (ahead > 0 ? home.right - f.x : f.x - home.left) - length * 0.3
        if f.burst.justSetOff {
            let free = min(bedFreeDistance(f, heading: ahead, besides: f.burst.restSpot), toWall)
            // A dart needs open sand ahead; without it the loach does not dart at all.
            if f.burst.pace > 2 && free < length * 1.5 { f.burst.stop(); return }
            guard free < length * 0.8 else { return }
            // It would rather slip across to another lane than turn round: turning back needs clear
            // sand behind, including beside the lane, and a loach that has just turned does not turn
            // straight back again. One boxed in for a long while turns back at the first chance.
            // At first it simply waits for the way to clear.
            guard f.burst.parkedFor > 1.5 else { f.burst.stop(); return }
            let boxedLong = f.burst.parkedFor > 3
            let up = f.y < (home.top + home.bottom) / 2
            if !boxedLong && bedIsClearAcross(f, up: up, home: home) { f.burst.sidestep(up: up); return }
            if bedFreeDistance(f, heading: -ahead, lane: boxedLong ? 0.025 : 0.04) >= length * 0.8 && (f.sinceLastTurn > 8 || boxedLong) {
                turnBack(&f)
                return
            }
            // Otherwise step across to another lane, toward the side with more sand if it is
            // clear, else the other side; boxed in on both, wait. Boxed in for long, it squeezes
            // through a narrower gap, and at last turns back and swims round regardless.
            let margin = boxedLong ? 0.018 : 0.03
            if bedIsClearAcross(f, up: up, home: home, margin: margin) {
                f.burst.sidestep(up: up)
            } else if bedIsClearAcross(f, up: !up, home: home, margin: margin) {
                f.burst.sidestep(up: !up)
            } else if f.burst.parkedFor > 6 {
                turnBack(&f)
            } else {
                f.burst.stop()
            }
        } else if f.burst.sidestepping {
            // A sidestep stops short of anyone lying in the lane it is moving into.
            if !bedIsClearAcross(f, up: f.burst.bearing > 0, home: home, margin: 0.02) { f.burst.stop() }
        } else if min(bedFreeDistance(f, heading: ahead, lane: abs(f.burst.bearing) > 0.3 ? 0.04 : nil, besides: f.burst.restSpot), toWall) < length * 0.8 {
            // Coasting to a stop covers about a third of a body length; a dart veering across
            // the bed also minds the next lane.
            f.burst.stop()
        }
    }

    /// Whether a bed resident can move `up` (or down) the bed without landing on a neighbour:
    /// nobody overlapping it side to side lies within `margin` (a crab: half as much again) in
    /// that direction.

    /// Whether a bed resident can move `up` (or down) the bed without landing on a neighbour:
    /// nobody overlapping it side to side lies within `margin` (a crab: half as much again) in
    /// that direction.
    func bedIsClearAcross(_ f: FishState, up: Bool, home: SwimRegion, margin: Double = 0.03) -> Bool {
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

    func turnBack(_ f: inout FishState) {
        f.facingRight.toggle()
        f.navigation.turnBack()
        f.reversalUrge = 0
        if f.turnDirection != 0 { f.lastTurnDirection = f.turnDirection; f.sinceLastTurn = 0 }
        f.turnDirection = 0
    }

    /// Whether `other` lies in the same lane on the bed as `f`: a loach gives a crab a wider berth
    /// than another loach, and a crab a loach likewise.

    /// Whether `other` lies in the same lane on the bed as `f`: a loach gives a crab a wider berth
    /// than another loach, and a crab a loach likewise.
    static func sharesLane(_ f: FishState, _ other: Neighbor, lane: Double? = nil) -> Bool {
        guard other.species.isBottomDweller,
              abs(other.depth - f.depth) < bedLayer || crabAndLoach(f.species, other.species) else { return false }
        let tolerance = lane ?? (crabAndLoach(f.species, other.species) && f.species != other.species ? 0.035
            : (f.species == .loach && other.species == .loach ? 0.025 : 0.015))
        return abs(bedGap(f.y, f.depth, other.y, other.depth)) < tolerance
    }

    /// Clear sand ahead of `f` in its lane before the nearest neighbour's edge, in scene widths.
    /// Neighbours lying within a body length of `besides` (where the loach means to lie down
    /// beside them) are not in its way.

    /// Clear sand ahead of `f` in its lane before the nearest neighbour's edge, in scene widths.
    /// Neighbours lying within a body length of `besides` (where the loach means to lie down
    /// beside them) are not in its way.
    func bedFreeDistance(_ f: FishState, heading: Double, lane: Double? = nil, besides spot: SIMD2<Double>? = nil) -> Double {
        let length = f.species.bodyLength * f.depth
        return neighbors.reduce(Double.infinity) { free, other in
            guard other.id != f.id, Self.sharesLane(f, other, lane: lane) else { return free }
            if let spot, hypot(other.x - spot.x, other.y - spot.y) < length { return free }
            let reach = (f.species.bedFootprint * f.depth + other.species.bedFootprint * other.depth) * 0.5
            let ahead = (other.x - f.x) * heading
            return ahead > 0 ? min(free, ahead - reach) : free
        }
    }

    /// Whether a neighbour on the bed lies just ahead, within `lookahead` beyond touching. A loach
    /// gives a crab a wider berth, so it never slips under the crab's legs.

    /// Whether a neighbour on the bed lies just ahead, within `lookahead` beyond touching. A loach
    /// gives a crab a wider berth, so it never slips under the crab's legs.
    func isBlockedOnBed(_ f: FishState, heading: Double, lookahead: Double = 0) -> Bool {
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

    /// Residents lying on the bed that touch at the same depth slide gently apart along the sand,
    /// whichever way they face, as bodies bump and settle side by side.
    /// How far apart side to side, as a share of their footprints, bottom dwellers keep. Loaches
    /// keep a little more room, so two never read as one long fish lying nose to tail, but crowd
    /// in at food.
    static func bedReachX(_ a: FishSpecies, _ b: FishSpecies, feeding: Bool = false) -> Double {
        if feeding { return 0.9 }
        if a == .loach && b == .loach { return 1.35 }
        // Shrimp keep a little room too, so two never stand with their heads run together.
        if a == .shrimp && b == .shrimp { return 1.15 }
        // A loach keeps its snout clear of a crab's spread legs.
        if crabAndLoach(a, b) && (a == .loach || b == .loach) { return 1.1 }
        return 0.9
    }

    /// How far apart two bed residents are, as a share of the room they keep (1 = just clear).
    /// A loach and a crab keep a box of room, so a loach never lies diagonally with its snout
    /// across the crab's spread legs; other pairs keep an ellipse.

    /// How far apart two bed residents are, as a share of the room they keep (1 = just clear).
    /// A loach and a crab keep a box of room, so a loach never lies diagonally with its snout
    /// across the crab's spread legs; other pairs keep an ellipse.
    static func bedSeparation(_ a: FishSpecies, _ b: FishSpecies, _ x: Double, _ y: Double) -> Double {
        crabAndLoach(a, b) && a != b ? max(abs(x), abs(y)) : hypot(x, y)
    }

    /// Two loaches both lying at rest, which may lie close alongside each other.

    /// Two loaches both lying at rest, which may lie close alongside each other.
    func bothResting(_ f: FishState, _ other: Neighbor) -> Bool {
        f.species == .loach && other.resting && f.burst.regime == .rest && !f.isEngaged
    }

    /// A crab away from food holds its ground; a loach that meets it goes round it, and is not
    /// the one to shove the crab along.

    /// A crab away from food holds its ground; a loach that meets it goes round it, and is not
    /// the one to shove the crab along.
    func holdsGround(_ f: FishState, against other: Neighbor) -> Bool {
        f.species == .crab && !f.isEngaged && other.species == .loach
    }

    func nudgeApartOnBed(_ f: inout FishState, region: SwimRegion, movement: Double) {
        // A shrimp tucked into its refuge is not shouldered out of it; neighbours make the room.
        if f.species == .shrimp && !f.isEngaged && f.shrimpBehavior.holdsPosition { return }
        // Nor is one in the middle of a tail flip, which is off the sand altogether.
        if f.species == .shrimp && f.shrimpBehavior.isEscaping { return }
        var push = 0.0
        for other in neighbors where other.id != f.id && other.species.isBottomDweller && !holdsGround(f, against: other)
            && (abs(other.depth - f.depth) < Self.bedLayer || (Self.keepApartAtAnyDepth(f.species, other.species) && !bothResting(f, other))) {
            let together = bothResting(f, other)
            let reachX = (f.species.bedFootprint * f.depth + other.species.bedFootprint * other.depth) * 0.5
                * (together ? 0.6 : Self.bedReachX(f.species, other.species, feeding: f.isChasingFood))
            let sx = f.x - other.x, sy = Self.bedGap(f.y, f.depth, other.y, other.depth)
            let gap = Self.bedSeparation(f.species, other.species, sx / reachX, sy / (together ? 0.01 : Self.bedReachY(f.species, other.species)))
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
}
