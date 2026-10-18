import Foundation

// Fishing extension: the rig in the water, and what the residents make of it.
//
// A fish that notices the bait looks it over from a body length away, then refuses it, nibbles
// pieces off it, or takes it whole. Taking it, the fish turns away with the bait in its mouth and
// the float slides under; strike within that moment and a hook that fits its mouth sets. Lures are
// followed while they move and hit on a twitch. Splashes, strikes, and a fish fighting on the line
// scatter the others, and a fish that has felt the hook stays wary for minutes.
extension AquariumSimulation {
    /// Reeling in a fight, in scene widths per movement unit (the reel speed at the default
    /// swimming speed, so a fight keeps its pace with the fish).
    static let reelPerMovement = FishingRig.reelSpeed / 0.5

    // MARK: The angler's controls

    mutating func startFishing(hook: HookKind, offering: Offering) {
        if rig != nil { changeTackle(hook: hook, offering: offering); return }
        rig = FishingRig(hook: hook, offering: offering, seed: entitySeed)
    }

    mutating func stopFishing() {
        rig = nil
        rigCrowd = 0
        for i in fish.indices where fish[i].angling != nil { fish[i].angling = nil }
    }

    /// New tackle is tied on straight away; a fish already on is played out on the old tackle.
    mutating func changeTackle(hook: HookKind, offering: Offering) {
        guard var r = rig, r.hook != hook || r.offering != offering else { return }
        switch r.phase {
        case .fighting, .landed:
            r.pendingTackle = (hook, offering)
            rig = r
        case .stowed, .retying:
            r.hook = hook; r.offering = offering
            rig = r
        case .flying, .sinking, .fishing:
            r.hook = hook; r.offering = offering
            rig = r
            reelIn()
        }
    }

    /// Casts toward a point in scene coordinates: the rig lands on the surface above it, and a
    /// bait under a float settles at that depth. Lures sink until retrieved. Returns false while
    /// the line is still out.
    @discardableResult mutating func cast(x: Double, y: Double) -> Bool {
        guard var r = rig, r.phase == .stowed, let theme else { return false }
        let v = visibleRegion
        let surface = Self.rigSurface(theme: theme, visible: v)
        r.surfaceY = surface
        r.castX = x.clamped(to: (v.left + 0.02)...(v.right - 0.03))
        r.setDepthY = y.clamped(to: (Self.sandHeight + 0.012)...(surface - 0.05))
        // The angler stands just off the right of the view, so the line runs up and away to that
        // side, and a retrieved lure swims back across the tank.
        r.rodTipX = max(r.castX + 0.16, v.right + 0.04)
        r.rodTipY = surface + 0.28
        r.flightFromX = r.rodTipX
        r.x = r.rodTipX; r.y = r.rodTipY
        r.flightTime = 0
        r.phase = .flying
        r.baitLeft = 1; r.soak = 0; r.speed = 0; r.sinceTwitch = 99
        r.floatX = r.castX; r.floatDip = 0; r.floatBob = 0
        r.holderID = nil; r.pendingStrike = false; r.crumbs.removeAll()
        r.emit(.cast)
        rig = r
        return true
    }

    /// A sharp lift of the rod: sets the hook in a fish holding the bait, or twitches the rig.
    mutating func strike() {
        if let r = rig, r.phase == .sinking || r.phase == .fishing { rig?.pendingStrike = true }
    }

    mutating func setReeling(_ on: Bool) { rig?.reeling = on }

    /// Brings the line straight in. A fish on has to be played out first.
    mutating func reelIn() {
        guard var r = rig else { return }
        switch r.phase {
        case .flying, .sinking, .fishing:
            stow(&r)
            r.emit(.reeledIn)
        case .landed:
            r.timer = 0
        default: break
        }
        rig = r
    }

    /// The take-in-hand version of the catch while it is shown, or nil.
    var landedCatch: CatchRecord? { rig?.landedCatch }

    mutating func drainFishingEvents() -> [FishingEvent] {
        guard let events = rig?.events, !events.isEmpty else { return [] }
        rig?.events.removeAll()
        return events
    }

    // MARK: Geometry

    /// The rig fishes at mid-tank depth, where it meets the surface here.
    static func rigSurface(theme: AquariumTheme, visible: SwimRegion) -> Double {
        BubbleField.surfaceY(theme: theme, depth: 0.95, visible: visible) - 0.004
    }

    /// Lowest a swimmer will go for bait. Koi, barbs, and bettas nose close to the bottom.
    static func reachBottom(_ species: FishSpecies) -> Double {
        switch species {
        case .koi, .golden, .cherry, .betta: return 0.13
        default: return 0.2
        }
    }

    static func mouth(of f: FishState) -> (x: Double, y: Double) {
        let reach = f.species == .crab ? 0 : f.species.bodySize * f.depth / 2300 * (f.species == .shrimp ? 0.18 : 0.35)
        return (f.x + cos(f.yaw) * reach, f.y + sin(f.pitch) * reach * TankScale.aspect * abs(cos(f.yaw)))
    }

    private func stow(_ r: inout FishingRig) {
        r.phase = .stowed
        r.holderID = nil; r.hookedID = nil
        r.speed = 0; r.floatDip = 0; r.pressure = 0; r.running = false
        r.crumbs.removeAll()
        if let next = r.pendingTackle { r.hook = next.hook; r.offering = next.offering; r.pendingTackle = nil }
    }

    /// A scene change takes the line out of the water.
    mutating func resetRig() {
        guard var r = rig else { return }
        stow(&r)
        r.landedCatch = nil
        rig = r
        for i in fish.indices where fish[i].angling != nil { fish[i].angling = nil }
    }

    // MARK: The rig, each step (before the fish move)

    mutating func advanceRig(dt: Double) {
        guard var r = rig else { return }
        r.disturbances = r.nextDisturbances
        r.nextDisturbances.removeAll()
        r.bobClock += dt
        r.floatBob *= exp(-dt * 4)
        r.sinceTwitch += dt
        r.splashAge += dt
        advanceCrumbs(&r, dt: dt)
        let previousX = r.x, previousY = r.y
        switch r.phase {
        case .stowed:
            r.speed = 0
        case .flying:
            r.flightTime += dt
            let t = min(1, r.flightTime / FishingRig.flightDuration)
            r.x = r.flightFromX + (r.castX - r.flightFromX) * t
            r.y = r.rodTipY + (r.surfaceY - r.rodTipY) * t + sin(t * .pi) * 0.1
            if t >= 1 { splashDown(&r) }
        case .sinking, .fishing:
            r.soak += dt
            if r.holderID == nil { driftAndRetrieve(&r, dt: dt) }
        case .fighting:
            if let id = r.hookedID, !fish.contains(where: { $0.id == id }) { stow(&r) }
        case .landed:
            r.timer -= dt
            // The fish was taken out of the tank in the meantime.
            if r.timer < -0.5 { r.landedCatch = nil; stow(&r); r.emit(.rigReady) }
        case .retying:
            r.timer -= dt
            if r.timer <= 0 { stow(&r); r.emit(.rigReady) }
        }
        if r.phase == .sinking || r.phase == .fishing {
            let moved = hypot(r.x - previousX, (r.y - previousY) / TankScale.aspect)
            r.speed += (moved / max(dt, 1e-6) - r.speed) * (1 - exp(-dt * 6))
        }
        // The float slides under while a fish has the bait or is on; otherwise it rides the ripples.
        // A big fish drags a shotted float right under; a danio can barely dip it.
        var under: Double = r.phase == .fighting ? 0.75 : 0
        if let holder = r.holderID, let f = fish.first(where: { $0.id == holder }) { under = min(1, 0.35 + 2 * Tackle.fightStrength(f.species)) }
        r.floatDip += (under - r.floatDip) * (1 - exp(-dt * (under > r.floatDip ? 9 : 3)))
        resolveStrike(&r)
        rig = r
        rigCrowd = fish.reduce(0) { $0 + (($1.angling?.phase.isAtBait ?? false) ? 1 : 0) }
    }

    /// After every fish has moved.
    mutating func finishRigStep() {
        guard var r = rig else { return }
        if r.phase == .fighting, let id = r.hookedID, let f = fish.first(where: { $0.id == id }) {
            r.floatX += (f.x - r.floatX) * 0.06
        }
        rig = r
    }

    private func splashDown(_ r: inout FishingRig) {
        r.x = r.castX
        r.y = r.offering.floats ? r.surfaceY - 0.003 : r.surfaceY - 0.008
        r.floatX = r.castX
        r.phase = r.offering.floats ? .fishing : .sinking
        r.splashAge = 0
        r.emit(.splash)
        // A fly settles softly on the film; a float and bait, or a lure, plop in.
        r.disturbances.append(.init(kind: .splash, x: r.castX, y: r.surfaceY, radius: r.offering.floats ? 0.07 : 0.15))
        if r.offering.floats { r.emit(.settled) }
    }

    private func driftAndRetrieve(_ r: inout FishingRig, dt: Double) {
        let sink = TankScale.height(cm: r.offering.sinkCM)
        let floor = Self.sandHeight + 0.006
        let home = min(r.rodTipX - 0.03, visibleRegion.right - 0.004)
        if r.offering.usesFloat {
            if r.reeling {
                // The float skates in toward the angler with the bait trailing up behind it.
                r.floatX = min(home + 0.01, r.floatX + FishingRig.reelSpeed * dt)
                r.y = min(r.surfaceY - 0.012, r.y + TankScale.height(cm: 1.6) * dt)
            } else if r.y > r.setDepthY {
                r.y = max(r.setDepthY, r.y - sink * dt)
            }
            // The bait hangs under the float, swaying a little in the current.
            let hang = r.floatX + sin(r.bobClock * 0.6) * 0.0022
            r.x += (hang - r.x) * (1 - exp(-dt * 2.2))
            if r.phase == .sinking && r.y <= r.setDepthY + 0.0005 { r.phase = .fishing; r.emit(.settled) }
            if r.floatX >= home { stow(&r); r.emit(.reeledIn) }
        } else if r.offering.floats {
            // A dry fly skates across the film when the line comes in.
            if r.reeling { r.x += FishingRig.retrieveSpeed * dt }
            r.y = r.surfaceY - 0.003
            if r.x >= home { stow(&r); r.emit(.reeledIn) }
        } else {
            if r.reeling {
                // A lure swims in toward the angler and planes slowly upward as it comes, a
                // spinner more than a weighted jig; paused, it sinks again.
                r.x += FishingRig.retrieveSpeed * dt
                r.y += TankScale.height(cm: r.offering == .softWorm ? 0.8 : 2.6) * dt
                if r.phase == .sinking { r.phase = .fishing }
            } else if r.y > floor {
                r.y = max(floor, r.y - sink * dt)
                if r.phase == .sinking && r.y <= floor { r.phase = .fishing; r.emit(.settled) }
            }
            r.y = min(r.y, r.surfaceY - 0.012)
            if r.x >= home { stow(&r); r.emit(.reeledIn) }
        }
        // Bread softens in the water and slowly falls apart.
        if r.offering == .bread && (r.phase == .sinking || r.phase == .fishing) { r.baitLeft = max(0, r.baitLeft - dt / 150) }
    }

    private func advanceCrumbs(_ r: inout FishingRig, dt: Double) {
        for i in r.crumbs.indices {
            r.crumbs[i].age += dt
            r.crumbs[i].y -= TankScale.height(cm: 0.45) * dt
            r.crumbs[i].x += sin(r.crumbs[i].age * 1.1 + r.crumbs[i].drift * 9) * 0.0016 * dt
        }
        r.crumbs.removeAll { $0.age > 7 || $0.y < Self.sandHeight }
        if r.offering == .bread, r.phase == .fishing, r.baitLeft > 0.05, r.holderID == nil, r.crumbs.count < 14, r.dice.chance(dt * 0.7) {
            shedCrumb(&r)
        }
    }

    private func shedCrumb(_ r: inout FishingRig) {
        guard r.crumbs.count < 16 else { return }
        r.crumbs.append(.init(x: r.x + r.dice.value(-0.003...0.003), y: r.y - 0.002, age: 0, size: r.dice.value(0.5...1.2), drift: r.dice.next()))
    }

    /// Lifting the rod. With a fish holding the bait, that sets the hook, or pulls the bait from
    /// its lips; with nothing there, the bait jumps (and a lure darts) through the water.
    private mutating func resolveStrike(_ r: inout FishingRig) {
        guard r.pendingStrike else { return }
        r.pendingStrike = false
        guard r.phase == .sinking || r.phase == .fishing else { return }
        if let holder = r.holderID, let i = fish.firstIndex(where: { $0.id == holder }) {
            var f = fish[i]
            let fit = Tackle.hookFit(f.species, r.hook)
            // Struck the instant the float twitches, the bait is pulled from its lips; a circle
            // hook wants no strike at all, only the fish turning away against a tight line.
            let timing = r.holdElapsed < 0.12 ? 0.55 : 1.0
            r.holderID = nil
            if r.dice.chance(fit * timing * (r.hook.setsItself ? 0.35 : 1)) {
                hook(&f, rig: &r)
            } else {
                r.emit(.missed(f.species))
                if !r.offering.isLure { r.baitLeft = max(0, r.baitLeft - 0.5) }
                f.wariness = min(1, f.wariness + 0.6)
                flee(&f, from: (r.x, r.y), rig: &r)
                // The hook springs back up through the water.
                r.y = min(r.surfaceY - 0.01, r.y + 0.03)
                r.floatBob = 1
            }
            fish[i] = f
            return
        }
        // Sometimes a fish nibbling right at the hook is pricked and caught.
        if let i = fish.firstIndex(where: { f in
            f.angling?.phase == .nibbling && f.angling?.backOff ?? 1 <= 0
                && hypot(Self.mouth(of: f).x - r.x, (Self.mouth(of: f).y - r.y) * 0.55) < FishingRig.mouthReach * 1.6 }),
           r.dice.chance(0.06 * Tackle.hookFit(fish[i].species, r.hook)) {
            var f = fish[i]
            hook(&f, rig: &r)
            fish[i] = f
            return
        }
        if fish.contains(where: { $0.angling.map { [.inspecting, .nibbling, .taking].contains($0.phase) } ?? false }) && !r.offering.isLure {
            r.emit(.struckEarly)
            // Yanked through their mouths, the soft bait tears.
            r.baitLeft = max(0, r.baitLeft - 0.25)
        }
        twitch(&r)
    }

    private func twitch(_ r: inout FishingRig) {
        switch r.offering {
        case .softWorm: r.y = min(r.surfaceY - 0.01, r.y + 0.032)
        case .spinner: r.x += 0.012; r.y = min(r.surfaceY - 0.01, r.y + 0.008)
        case .dryFly: r.x += 0.005; r.floatBob = 1
        default:
            r.y = min(r.surfaceY - 0.012, r.y + 0.014)
            r.floatBob = min(1, r.floatBob + 0.7)
        }
        r.sinceTwitch = 0
        r.disturbances.append(.init(kind: .twitch, x: r.x, y: r.y, radius: 0.09))
    }

    private mutating func hook(_ f: inout FishState, rig r: inout FishingRig) {
        r.phase = .fighting
        r.hookedID = f.id
        r.holderID = nil
        r.stamina = 1
        r.pressure = 0.3
        r.slackTime = 0; r.overload = 0; r.fightTime = 0; r.thrashClock = 0
        // The first run comes the moment it feels the hook: away from the angler, and down.
        r.running = true
        r.runRemaining = r.dice.value(0.6...1.2) * (0.6 + Tackle.fightStrength(f.species))
        r.runAngle = runAngle(for: f, rig: &r, firstRun: true)
        let m = Self.mouth(of: f)
        r.x = m.x; r.y = m.y
        r.lineLength = r.lineDistance(m.x, m.y)
        f.angling = AnglingResponse(phase: .hooked, timer: 0)
        f.feeding = nil
        r.emit(.hooked(f.species))
        r.nextDisturbances.append(.init(kind: .thrash, x: f.x, y: f.y, radius: 0.16))
    }

    /// Away from the rod and usually down toward cover; deep-bodied fish bore down, small ones
    /// bolt anywhere, and now and then a fish swims straight at the angler, throwing slack.
    private func runAngle(for f: FishState, rig r: inout FishingRig, firstRun: Bool = false) -> Double {
        var ax = f.x - r.rodTipX, ay = (f.y - r.rodTipY) / TankScale.aspect
        let length = max(1e-6, hypot(ax, ay))
        ax /= length; ay /= length
        if !firstRun && r.dice.chance(0.18) { ax = -ax; ay = -ay * 0.3 }
        let dive: Double = [.koi, .loach, .pearl, .golden].contains(f.species) ? 0.7 : 0.25
        return atan2(ay - dive, ax) + r.dice.normal(deviation: 0.45)
    }

    // MARK: Each fish

    /// Commotion, and the phases in which the line, not the fish, decides where it goes.
    /// Returns true when the fish's movement this step is fully handled here.
    mutating func anglingOverride(_ f: inout FishState, dt: Double, movement: Double, home: SwimRegion) -> Bool {
        if f.wariness > f.learned { f.wariness = max(f.learned, f.learned + (f.wariness - f.learned) * exp(-dt / 110)) }
        guard var r = rig else {
            if f.angling != nil { f.angling = nil }
            return false
        }
        for d in r.disturbances { react(&f, to: d, rig: &r) }
        guard let a = f.angling else { rig = r; return false }
        var handled = false
        switch a.phase {
        case .hooked:
            if r.hookedID == f.id { fight(&f, rig: &r, dt: dt, movement: movement) } else { f.angling = nil }
            handled = f.angling?.phase == .hooked || f.angling?.phase == .landed
        case .landed:
            handled = true
            if r.timer <= 0 { release(&f, rig: &r, home: home) }
        case .gripping:
            handled = carryCrab(&f, rig: &r, dt: dt)
        case .dropping:
            f.y -= TankScale.height(cm: 4) * dt
            f.vx = 0; f.vy = 0
            if f.y <= home.top { f.y = home.top; f.angling = nil; f.wariness = max(f.wariness, 0.5) }
            handled = true
        default:
            break
        }
        rig = r
        return handled
    }

    private func react(_ f: inout FishState, to d: FishingRig.Disturbance, rig r: inout FishingRig) {
        if let phase = f.angling?.phase, [.hooked, .landed, .dropping, .released].contains(phase) { return }
        let distance = hypot(f.x - d.x, (f.y - d.y) * 0.55)
        guard distance < d.radius else { return }
        let bold = ((f.personality.boldness - 0.78) / 0.5).clamped(to: 0...1)
        switch d.kind {
        case .splash:
            // A plop at the top barely reaches the bed.
            if f.species.isBottomDweller { return }
            // Tank fish half expect food when something drops in, the bold ones most of all.
            if f.angling == nil && f.wariness < 0.3 && Tackle.appeal(f.species, r.offering) > 0.2
                && f.dice.chance((r.offering.soundsLikeFood ? 0.25 : 0.1) + 0.3 * bold) {
                // It sounds like feeding time: the bold ones come to look.
                f.angling = AnglingResponse(phase: .inspecting, timer: f.dice.exponential(mean: 1.4) + 0.4, side: f.x >= r.castX ? 1 : -1)
                r.emit(.curious(f.species))
            } else if f.dice.chance(0.6 - 0.3 * bold) {
                flee(&f, from: (d.x, d.y), rig: &r)
                r.emit(.spooked(f.species))
            }
        case .twitch:
            guard var a = f.angling else { return }
            if a.phase == .following || (a.phase == .inspecting && r.offering.isLure) {
                // A lure that darts like fleeing prey triggers the chase.
                if f.dice.chance(Tackle.aggression(f.species) * 0.75) { a.phase = .taking; a.age = 0; f.angling = a }
            } else if a.phase == .gripping {
                a.phase = .dropping; f.angling = a
                r.emit(.crabLetGo)
            } else if a.phase == .nibbling || a.phase == .taking {
                // The bait jerked from under its nose: it starts back and is warier, but greed keeps it near.
                f.wariness = min(1, f.wariness + 0.3)
                a.backOff = max(a.backOff, 0.8)
                a.phase = .nibbling
                f.angling = a
            } else if a.phase == .inspecting {
                if f.dice.chance(Tackle.caution(f.species)) { flee(&f, from: (d.x, d.y), rig: &r) } else { f.wariness = min(1, f.wariness + 0.3) }
            }
        case .thrash:
            if f.dice.chance(0.55 + 0.4 * (1 - distance / d.radius)) { flee(&f, from: (d.x, d.y), rig: &r) }
        }
    }

    private func flee(_ f: inout FishState, from point: (x: Double, y: Double), rig r: inout FishingRig) {
        if r.holderID == f.id { r.holderID = nil }
        let away: Double = f.x >= point.x ? 1 : -1
        let span = (f.species.isBottomDweller ? 0.1 : 0.2) * f.dice.value(0.7...1.2)
        let y = f.species.isBottomDweller ? f.y : f.y + (f.y >= point.y ? 0.04 : -0.07)
        f.angling = AnglingResponse(phase: .fleeing, timer: f.dice.value(0.9...2.0), x: f.x + away * span, y: y)
        f.wariness = min(1, f.wariness + 0.12)
    }

    private func leave(_ f: inout FishState, _ a: inout AnglingResponse, from r: FishingRig) {
        let away: Double = f.x >= r.x ? 1 : -1
        a.phase = .refusing
        a.age = 0
        a.timer = f.dice.value(1.2...2.6)
        a.x = f.x + away * f.dice.value(0.06...0.14)
        a.y = f.y + f.dice.value(-0.02...0.03)
    }

    /// Bait in the water reaches a fish by its scent, spreading over the first seconds; a lure by
    /// moving like something alive. Hungry fish come sooner, wary ones hardly at all.
    mutating func noticeRig(_ f: inout FishState, dt: Double, home: SwimRegion, theme: AquariumTheme) {
        guard let r = rig, r.isFishable, rigCrowd < 5 else { return }
        let offering = r.offering
        let appeal = Tackle.appeal(f.species, offering)
        guard appeal > 0 else { return }
        if f.species.isBottomDweller {
            let bed = Self.region(for: f.species, theme: theme)
            guard r.y <= Self.region(for: .loach, theme: theme).top + 0.03, r.x >= bed.left - 0.02, r.x <= bed.right + 0.02 else { return }
        } else {
            guard r.y >= Self.reachBottom(f.species) - 0.01 else { return }
            // Only fish that feed at the top rise to a fly.
            if offering.floats && Self.region(for: f.species, theme: theme).top < 0.7 { return }
        }
        let distance = hypot(r.x - f.x, (r.y - f.y) * 0.55)
        let awareness: Double
        if f.species.isBottomDweller { awareness = 0.11 }
        else if offering == .spinner { awareness = r.speed > 0.008 ? 0.22 : 0.1 }
        else if offering.floats { awareness = 0.22 }
        else { awareness = 0.24 }
        guard distance < awareness else { return }
        let draw: Double
        if offering.isLure { draw = offering.needsMotion ? (r.speed > 0.008 ? 1 : 0.06) : (r.lureIsLively ? 1 : 0.35) }
        else { draw = min(1, 0.35 + r.soak / 12) }
        let hunger = 0.35 + 0.65 * f.appetite
        let crowd = rigCrowd > 0 ? 1.4 : 1
        let rate = appeal * draw * hunger * crowd * (1 - f.wariness) * 0.8 * (1 - distance / awareness * 0.5)
        guard f.dice.chance(rate * dt) else { return }
        let side: Double = f.x >= r.x ? 1 : -1
        if offering == .spinner || offering == .softWorm {
            f.angling = AnglingResponse(phase: .following, timer: f.dice.exponential(mean: 5) + 3, side: side)
            rig?.emit(.following(f.species))
        } else {
            let caution = Tackle.caution(f.species)
            f.angling = AnglingResponse(phase: .inspecting, timer: f.dice.exponential(mean: 0.6 + 2.6 * caution) + 0.3, side: side)
            rig?.emit(.interest(f.species))
        }
        rigCrowd += 1
    }

    /// Where a fish busy with the rig swims, and what it decides when it gets there.
    mutating func anglingGoal(_ f: inout FishState, goal: inout SteeringGoal, dt: Double, home: SwimRegion) {
        guard var a = f.angling, let r = rig else { f.angling = nil; return }
        a.age += dt
        let length = f.species.bodyLength * f.depth
        let mouth = Self.mouth(of: f)
        let gap = hypot(r.x - mouth.x, (r.y - mouth.y) * 0.55)
        var region = goal.region
        if !f.species.isBottomDweller {
            // Chasing a lure, a fish follows it down almost to the sand.
            let floor = a.phase == .following || (a.phase == .taking && r.offering.isLure) ? Self.sandHeight + 0.03 : Self.reachBottom(f.species) - 0.01
            region.bottom = min(region.bottom, max(floor, r.y - 0.03))
            region.top = max(region.top, min(r.surfaceY - 0.008, r.y + 0.03))
        }
        // A fish put back at the surface, or a crab lifted off the sand, is never snapped into its band.
        region.top = max(region.top, f.y)
        region.bottom = min(region.bottom, f.y)
        region = region.intersecting(visibleRegion)
        goal.region = region
        goal.targetFood = nil
        let atBait = r.isFishable || r.holderID == f.id
        // The pivot point that puts the mouth on the bait.
        let biteX = r.x - (mouth.x - f.x), biteY = r.y - (mouth.y - f.y)
        switch a.phase {
        case .inspecting:
            if !atBait || a.age > 14 { leave(&f, &a, from: r); break }
            goal.x = r.x + a.side * (length * 0.75 + 0.012); goal.y = r.y - 0.004
            if gap < length * 1.5 + 0.03 { a.timer -= dt }
            if a.timer <= 0 { decide(&f, &a) }
        case .following:
            if !r.isFishable { leave(&f, &a, from: r); break }
            // A body length behind the lure, matching its pace.
            let behind: Double = r.rodTipX >= r.x ? -1 : 1
            goal.x = r.x + behind * (length * 0.9 + 0.008); goal.y = r.y - 0.003
            a.timer -= dt * (r.lureIsLively ? 1 : 2)
            // Close behind it, a follower hits a lure that keeps swimming, and often one that
            // suddenly stops and drops, the way prey falters; otherwise it may lose interest.
            let urge = Tackle.appeal(f.species, r.offering) * Tackle.aggression(f.species)
            if gap < length * 2 + 0.03 && f.dice.chance(dt * urge * (r.lureIsLively ? 1.4 : 1.0)) {
                a.phase = .taking; a.age = 0
            } else if a.timer <= 0 || (!r.lureIsLively && f.dice.chance(dt * 0.3)) {
                rig?.emit(.refused(f.species))
                leave(&f, &a, from: r)
            }
        case .nibbling:
            if !atBait || a.age > 25 { leave(&f, &a, from: r); break }
            if a.backOff > 0 {
                a.backOff -= dt
                goal.x = r.x + a.side * (length * 0.45 + 0.008); goal.y = r.y - 0.003
            } else {
                goal.x = biteX; goal.y = biteY
                if gap < FishingRig.mouthReach { peck(&f, &a) }
            }
        case .taking:
            if !atBait || a.age > 5 { leave(&f, &a, from: r); break }
            goal.x = biteX; goal.y = biteY
            if gap < FishingRig.mouthReach * 1.3 {
                if r.holderID == nil { beginHold(&f, &a) } else { a.phase = .inspecting; a.timer = 0.6 }
            }
        case .holding:
            guard r.holderID == f.id else { leave(&f, &a, from: r); break }
            goal.x = a.x; goal.y = a.y
            rig?.holdElapsed += dt
            if let held = rig, held.holdElapsed >= held.holdLimit { endHold(&f, &a) }
        case .gripping:
            goal.x = biteX; goal.y = biteY
        case .fleeing, .refusing, .released:
            goal.x = a.x; goal.y = a.y
            a.timer -= dt
            if a.timer <= 0 { f.angling = nil; (goal.x, goal.y) = region.constrain(x: goal.x, y: goal.y); return }
        case .hooked, .landed, .dropping:
            break
        }
        (goal.x, goal.y) = region.constrain(x: goal.x, y: goal.y)
        // Hooking replaced the response; everything else carries on with the updated one.
        if f.angling?.phase != .hooked { f.angling = a }
    }

    /// Looked it over: refuse it, pick at it, or take it.
    private mutating func decide(_ f: inout FishState, _ a: inout AnglingResponse) {
        guard let r = rig else { return }
        let fit = Tackle.hookFit(f.species, r.hook)
        let bold = ((f.personality.boldness - 0.78) / 0.5).clamped(to: 0...1)
        let crowd = Double(max(0, rigCrowd - 1))
        var refusal = Tackle.caution(f.species) * (0.3 + r.hook.visibility) * (r.offering.isLure ? 0.6 : 1) + f.wariness * 0.7
            + (!r.offering.isLure && r.speed > 0.006 ? 0.25 : 0) - min(0.25, crowd * 0.08) - (f.appetite - 0.5) * 0.3
        if f.species.isInvertebrate { refusal = 0.05 }
        if f.dice.chance(refusal.clamped(to: 0.03...0.92)) {
            rig?.emit(.refused(f.species))
            leave(&f, &a, from: r)
            return
        }
        // Big mouths inhale a bait whole; small ones mostly pick at it.
        var take = fit >= 0.3 ? 0.3 + 0.25 * bold + min(0.2, crowd * 0.07) + (Tackle.biteSize(f.species) >= 1 ? 0.25 : 0) : 0.05
        if r.offering.isLure { take += 0.3 }
        if f.species.isInvertebrate { take = 0 }
        a.age = 0
        if f.dice.chance(take) {
            a.phase = .taking
        } else {
            a.phase = .nibbling
            a.backOff = 0
            a.maxPecks = f.species.isInvertebrate ? Int(f.dice.value(8...14)) : Int(f.dice.value(2...5.99))
        }
    }

    private mutating func peck(_ f: inout FishState, _ a: inout AnglingResponse) {
        guard var r = rig else { return }
        a.pecks += 1
        a.backOff = f.dice.value(f.species.isInvertebrate ? 0.35...0.9 : 0.3...0.85)
        let bite = Tackle.biteSize(f.species)
        if !r.offering.isLure {
            r.baitLeft = max(0, r.baitLeft - r.offering.peckLoss * bite * Tackle.baitHold(r.hook))
            if r.offering == .bread || r.offering == .pellet { shedCrumb(&r); shedCrumb(&r) }
        }
        r.floatBob = min(1, r.floatBob + 0.25 + 0.3 * min(1, bite))
        r.emit(.nibble(f.species))
        f.appetite = max(0, f.appetite - 0.04)
        if !r.offering.isLure && r.baitLeft <= 0.04 {
            r.baitLeft = 0
            r.emit(.baitStolen(f.species))
            f.appetite = max(0, f.appetite - 0.25)
            rig = r
            leave(&f, &a, from: r)
            return
        }
        if f.species == .crab && f.dice.chance(0.3) {
            // A crab grabs the bait in its claws and hangs on.
            a.phase = .gripping
            a.timer = f.dice.value(2...5)
            a.grip = f.dice.value(0.8...2.4)
            a.lifted = 0
            a.announced = false
        } else if a.pecks >= a.maxPecks {
            if Tackle.hookFit(f.species, r.hook) >= 0.3 && f.dice.chance(0.45) { a.phase = .taking; a.age = 0 }
            else { rig = r; leave(&f, &a, from: r); return }
        }
        rig = r
    }

    private mutating func beginHold(_ f: inout FishState, _ a: inout AnglingResponse) {
        guard var r = rig else { return }
        // A fish hitting a lure that is being reeled often hooks itself against the moving line.
        if r.offering.isLure && r.reeling && !r.offering.floats {
            // A circle hook needs a fish turning away on a still line; on a moving lure it rarely catches.
            if r.dice.chance(Tackle.hookFit(f.species, r.hook) * (r.hook.setsItself ? 0.25 : 0.7)) {
                hook(&f, rig: &r)
                rig = r
                return
            }
            r.emit(.missed(f.species))
            rig = r
            leave(&f, &a, from: r)
            return
        }
        r.emit(.take(f.species))
        r.holderID = f.id
        r.holdElapsed = 0
        // A lure is mouthed a little more briefly than food, but always long enough to react.
        r.holdLimit = max(0.6, f.dice.value(Tackle.holdTime(f.species)) * (r.offering.isLure ? 0.85 : 1))
        rig = r
        // It turns back the way it came with the bait, and a little down.
        a.phase = .holding
        a.age = 0
        a.x = f.x + a.side * 0.08
        a.y = f.y - 0.02
    }

    /// Mouthed long enough: it feels the hook and spits it, unless a circle hook catches in the
    /// corner of its jaw as it turns.
    private mutating func endHold(_ f: inout FishState, _ a: inout AnglingResponse) {
        guard var r = rig else { return }
        r.holderID = nil
        if r.hook.setsItself && r.dice.chance(Tackle.hookFit(f.species, r.hook) * 0.95) {
            hook(&f, rig: &r)
            rig = r
            return
        }
        if !r.offering.isLure { r.baitLeft = max(0, r.baitLeft - 0.35 * Tackle.biteSize(f.species)) }
        r.emit(.spat(f.species))
        f.wariness = min(1, f.wariness + 0.25)
        rig = r
        leave(&f, &a, from: r)
    }

    /// A crab hanging on to the bait rides up with it as the line comes in, then lets go.
    private func carryCrab(_ f: inout FishState, rig r: inout FishingRig, dt: Double) -> Bool {
        guard var a = f.angling else { return false }
        guard r.phase == .fishing || r.phase == .sinking else {
            a.phase = .dropping; f.angling = a
            return true
        }
        a.timer -= dt
        let lifting = r.reeling || r.y > f.y + 0.012
        if lifting {
            a.lifted += dt
            f.x = r.x; f.y = r.y - 0.008
            f.vx = 0; f.vy = 0
            r.baitLeft = max(0, r.baitLeft - dt * 0.03)
            if !a.announced && a.lifted > 0.2 { r.emit(.crabClinging); a.announced = true }
            if a.lifted >= a.grip { a.phase = .dropping; r.emit(.crabLetGo) }
            f.angling = a
            return true
        }
        // On the sand it keeps tearing at the bait with its claws.
        r.baitLeft = max(0, r.baitLeft - dt * 0.02)
        if r.baitLeft <= 0.04 {
            r.baitLeft = 0
            r.emit(.baitStolen(.crab))
            leave(&f, &a, from: r)
        } else if a.timer <= 0 {
            leave(&f, &a, from: r)
        }
        f.angling = a
        return false
    }

    /// How energetically a fish busy with the rig swims, relative to its cruise speed.
    func anglingActivity(_ f: FishState, _ a: AnglingResponse) -> Double {
        switch a.phase {
        case .inspecting:
            // It swims over at an ordinary pace, then slows to look the bait over.
            guard let r = rig else { return 0.4 }
            let m = Self.mouth(of: f)
            let gap = hypot(r.x - m.x, (r.y - m.y) * 0.55)
            return gap > f.species.bodyLength * f.depth * 2.5 + 0.04 ? 1.1 : 0.35
        case .following:
            // Keeping pace with the lure (activity 1 is cruise speed at the default swimming speed).
            // A follower that has fallen behind sprints to close the gap.
            guard let r = rig else { return 1 }
            let m = Self.mouth(of: f)
            let behind = hypot(r.x - m.x, (r.y - m.y) * 0.55) > f.species.bodyLength * f.depth * 2 + 0.03
            // Chasing prey, a fish bursts to four or five times its cruising speed.
            return ((r.speed / max(0.001, f.species.cruiseSpeed * 0.5)) * (behind ? 2 : 1.1)).clamped(to: behind ? 2...4.5 : 0.4...2.8)
        case .nibbling: return a.backOff > 0 ? 0.35 : 0.9
        case .taking: return rig?.offering.isLure == true ? 2.6 : 1.4
        case .holding: return 0.55
        case .fleeing: return 2.8
        case .refusing: return 0.7
        case .released: return 2.2
        case .gripping: return 0.3
        case .hooked, .landed, .dropping: return 0
        }
    }

    /// The fish holding the bait carries it, and drags the float after it.
    mutating func carryRig(_ f: FishState) {
        let m = Self.mouth(of: f)
        rig?.x = m.x; rig?.y = m.y
        if let floatX = rig?.floatX { rig?.floatX = floatX + (f.x - floatX) * 0.08 }
    }

    // MARK: The fight

    /// A fish of a gram or two is simply lifted out with the rod. Heavier fish run and rest: a
    /// running fish takes line against the drag, which caps the pressure on a still reel, but
    /// cranking the reel into a run shocks the line past the drag and something gives. A slack
    /// line lets a head-shaking fish throw the hook. Reel while it rests, let go while it runs,
    /// and it tires and comes to the surface.
    private mutating func fight(_ f: inout FishState, rig r: inout FishingRig, dt: Double, movement: Double) {
        let species = f.species
        let strength = Tackle.fightStrength(species)
        // Only a koi has the weight to pull line through a drag; a barb or gourami dives and
        // shakes its head against the rod but always comes in.
        let takesLine = strength >= 0.6
        let drag = r.hook.strength * 0.8
        r.fightTime += dt
        r.shakeClock += dt * (r.running ? 6 : 9)
        r.runRemaining -= dt
        if r.running {
            r.thrashClock += dt
            if r.thrashClock > 0.7 { r.thrashClock = 0; r.nextDisturbances.append(.init(kind: .thrash, x: f.x, y: f.y, radius: 0.12)) }
            if r.runRemaining <= 0 || r.stamina < 0.05 { r.running = false; r.runRemaining = r.dice.exponential(mean: 0.9) + 0.35 }
        } else if r.runRemaining <= 0 && r.stamina > 0.1 && r.dice.chance(min(1, dt * (0.5 + 1.8 * r.stamina))) {
            r.running = true
            r.runRemaining = (r.dice.exponential(mean: 0.45 + 1.1 * strength) + 0.35) * (0.45 + 0.55 * r.stamina)
            r.runAngle = runAngle(for: f, rig: &r)
            if takesLine { r.emit(.run(species)) }
        }
        let away = atan2((f.y - r.rodTipY) / TankScale.aspect, f.x - r.rodTipX)
        let direction = r.running ? r.runAngle : away
        let speed = species.cruiseSpeed * f.personality.boldness * (r.running ? 2.2 + 1.8 * r.stamina : 0.45 * r.stamina)
        let startX = f.x, startY = f.y
        var nx = f.x + cos(direction) * speed * movement
        var ny = f.y + sin(direction) * speed * movement * TankScale.aspect
        // Water only: between the sand and the surface film, inside the view.
        let top = r.surfaceY - 0.012
        let bottom = Self.sandHeight + (species.isBottomDweller ? 0.006 : 0.03)
        if nx < visibleRegion.left || nx > visibleRegion.right { r.runAngle = .pi - r.runAngle; nx = nx.clamped(to: visibleRegion.left...visibleRegion.right) }
        if ny < bottom { r.runAngle = -r.runAngle; ny = bottom }
        // The angler reels: the line shortens, more slowly against a strong, fresh fish.
        if r.reeling {
            let effort = 1 - 0.55 * min(1, strength * r.stamina * (r.running ? 1.4 : 0.6))
            // A small fish is swung up with the rod faster than any reel turns.
            let lift = 1 + 2.5 * max(0, 0.6 - strength) / 0.6
            r.lineLength = max(0.01, r.lineLength - Self.reelPerMovement * movement * effort * lift)
        }
        let pull = strength * (0.2 + 0.8 * r.stamina) * (r.running ? 1 : 0.3) + strength * 0.18 * r.stamina * max(0, sin(r.shakeClock))
        let reach = r.lineDistance(nx, ny)
        let target: Double
        if reach < r.lineLength - 0.012 { target = r.reeling ? 0.14 : 0.02 }
        // Cranking into a run shocks the line well past the drag.
        // Horsing a smaller fish while it dives can tear the hook from its lip.
        else if r.reeling { target = r.running ? (takesLine ? pull * 1.7 + 0.25 : pull * 1.3 + 0.3) : pull + 0.3 }
        // The bent rod keeps a light pressure on a still reel, and the drag slips before it can climb past its setting.
        else { target = min(pull * 0.6 + 0.08, drag) }
        r.pressure += (target - r.pressure) * (1 - exp(-dt * 7))
        if reach > r.lineLength {
            // A running fish takes line off a still reel through the drag; a small fish has no run in it.
            if (takesLine && r.running && !r.reeling) || r.pressure > drag * 0.97 {
                r.lineLength = reach
            } else {
                let dx = nx - r.rodTipX, dy = (ny - r.rodTipY) / TankScale.aspect
                let k = r.lineLength / max(1e-6, hypot(dx, dy))
                nx = r.rodTipX + dx * k
                ny = r.rodTipY + dy * k * TankScale.aspect
            }
        }
        ny = min(ny, top)
        // Too much pressure for too long, and something gives.
        if r.pressure > r.hook.strength { r.overload += dt } else { r.overload = max(0, r.overload - dt * 0.6) }
        if r.pressure < 0.1 { r.slackTime += dt } else { r.slackTime = max(0, r.slackTime - dt * 1.5) }
        // On a slack line every head shake may loosen the barb: a small, fine hook has the lightest
        // hold, and a circle hook in the corner of the jaw almost never comes out.
        let looseness = (r.hook.setsItself ? 0.05 : (r.hook == .fine ? 0.35 : 0.3)) * Tackle.shakiness(species)
        let thrown = r.slackTime > 0.5 && r.dice.chance(dt * looseness)
        if r.overload > 0.3 || thrown {
            f.x = nx; f.y = ny
            loseFish(&f, rig: &r, snapped: r.overload > 0.3, takesLine: takesLine)
            return
        }
        r.stamina = max(0, r.stamina - dt / Tackle.staminaSeconds(species) * (r.running ? 1.3 : 0.5) * (0.4 + r.pressure))
        f.x = nx; f.y = ny
        // Brought up to the surface: a beaten fish is netted; a fresh one crashes about and dives.
        if ny >= top - 0.004 {
            if r.stamina < 0.4 || strength < 0.3 {
                land(&f, rig: &r)
                return
            }
            if !r.running {
                r.running = true
                r.runAngle = -.pi / 2 + r.dice.normal(deviation: 0.5)
                r.runRemaining = r.dice.value(0.5...1.0)
                r.emit(.surfaceThrash(species))
                r.nextDisturbances.append(.init(kind: .thrash, x: f.x, y: f.y, radius: 0.15))
            }
        }
        // How it looks: running, it swims where it runs; holding against the line it faces away
        // and is dragged tail first; beaten, it comes in head first. Head shakes throughout.
        f.vx = (nx - startX) / max(movement, 1e-6)
        f.vy = (ny - startY) / max(movement, 1e-6)
        let towardRod: Double = r.rodTipX >= f.x ? 0 : .pi
        var targetYaw: Double
        if r.running { targetYaw = cos(direction) >= 0 ? 0 : .pi }
        else if r.stamina < 0.35 { targetYaw = towardRod }
        else { targetYaw = towardRod + .pi }
        targetYaw += sin(r.shakeClock) * 0.32 * r.stamina * (r.running ? 0.4 : 1) + sin(r.fightTime * 0.7) * 0.18
        let previousYaw = f.yaw, previousYawVelocity = f.yawVelocity
        let requested = (Self.angleDifference(targetYaw, f.yaw) * 4).clamped(to: -7...7)
        f.yawVelocity += (requested - f.yawVelocity) * (1 - exp(-movement * 14))
        f.yaw = atan2(sin(f.yaw + f.yawVelocity * movement), cos(f.yaw + f.yawVelocity * movement))
        f.facingRight = cos(f.yaw) >= 0
        f.turnDirection = 0
        let travelled = hypot(f.vx, f.vy / TankScale.aspect)
        f.forwardSpeed = travelled
        let headUp = !r.running && r.stamina < 0.35 ? 0.35 : (r.running ? 0 : -0.12)
        let pitchGoal = (r.running ? FishState.pitchTarget(species: species, vx: f.vx, vy: f.vy, yawRate: f.yawVelocity, chasing: true) : headUp)
        f.pitch += ((pitchGoal - f.pitch) * (1 - exp(-movement * 6))).clamped(to: -movement * 1.2...movement * 1.2)
        f.depth += (r.depth - f.depth) * (1 - exp(-dt * 1.5))
        f.activity = r.running ? 2.5 : 1
        f.stroke.advance(delta: movement, species: species, speed: travelled / species.cruiseSpeed + (r.running ? 0.6 : 0.8),
            acceleration: r.running ? 1.5 : 0.4, turnRate: Self.angleDifference(f.yaw, previousYaw) / max(movement, 1e-6),
            turnAcceleration: (f.yawVelocity - previousYawVelocity) / max(movement, 1e-6))
        f.finPhase += movement * f.stroke.tailRate * (species == .loach ? 1.3 : 1)
        let m = Self.mouth(of: f)
        r.x = m.x; r.y = m.y
    }

    private func loseFish(_ f: inout FishState, rig r: inout FishingRig, snapped: Bool, takesLine: Bool) {
        let species = f.species
        if snapped && !takesLine {
            // Too much force on a small fish: the hook tears free and the rig springs back.
            r.emit(.hookPulled(species))
            r.phase = .fishing
            if !r.offering.isLure { r.baitLeft = 0 }
            r.sinceTwitch = 99
        } else if snapped {
            r.emit(r.hook == .fine ? .hookStraightened(species) : .lineSnapped(species))
            r.phase = .retying
            r.timer = FishingRig.retieDuration
        } else {
            r.emit(.threwHook(species))
            // The hook comes free and the empty rig hangs where the fish was.
            r.phase = .fishing
            if !r.offering.isLure { r.baitLeft = 0 }
            r.sinceTwitch = 99
        }
        r.hookedID = nil
        r.running = false
        r.pressure = 0
        f.wariness = 1
        flee(&f, from: (r.rodTipX, r.rodTipY), rig: &r)
    }

    private func land(_ f: inout FishState, rig r: inout FishingRig) {
        let length = Tackle.lengthCM(f.species, id: f.id)
        let weight = (Tackle.weightGrams(f.species, lengthCM: length) * 10).rounded() / 10
        let record = CatchRecord(species: f.species, lengthCM: length, weightGrams: weight, hook: r.hook, offering: r.offering,
                                 fishID: f.id, caughtBefore: r.caughtIDs.contains(f.id))
        r.caughtIDs.insert(f.id)
        r.phase = .landed
        r.timer = FishingRig.landedDuration
        r.landedCatch = record
        r.hookedID = nil
        r.running = false
        r.pressure = 0
        f.angling = AnglingResponse(phase: .landed, timer: 0)
        f.learned = min(0.5, f.learned + 0.1)
        f.vx = 0; f.vy = 0; f.forwardSpeed = 0
        r.emit(.landed(record))
        r.nextDisturbances.append(.init(kind: .thrash, x: f.x, y: f.y, radius: 0.18))
    }

    /// Back it goes, slipped in beside the angler: it shoots down and away to its usual water,
    /// and stays wary of baits for a good while.
    private func release(_ f: inout FishState, rig r: inout FishingRig, home: SwimRegion) {
        f.x = (r.rodTipX - 0.07).clamped(to: visibleRegion.left...visibleRegion.right)
        f.y = r.surfaceY - 0.03
        f.yaw = .pi; f.facingRight = false; f.yawVelocity = 0; f.pitch = -0.3
        f.depth = r.depth
        f.wariness = 1
        f.appetite = min(f.appetite, 0.15)
        let target = home.constrain(x: f.x - 0.2, y: (home.bottom + home.top) / 2)
        f.angling = AnglingResponse(phase: .released, timer: 3, x: target.0, y: target.1)
        r.landedCatch = nil
        stow(&r)
        r.emit(.released(f.species))
        r.emit(.rigReady)
    }
}
