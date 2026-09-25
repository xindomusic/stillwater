import Foundation

/// Real-world scale of the scene, so bubbles, food, and sand move at physical speeds.
enum TankScale {
    /// The visible water column is about this tall.
    static let waterHeightCM = 30.0
    /// Scene widths per scene height (the 1935×812 artwork).
    static let aspect = 1935.0 / 812.0

    /// Scene heights covered by `cm` centimetres.
    static func height(cm: Double) -> Double { cm / waterHeightCM }
    /// Scene widths covered by `cm` centimetres.
    static func width(cm: Double) -> Double { cm / (waterHeightCM * aspect) }
    /// On-screen diameter in points for `mm` millimetres, given the artwork's height in points.
    static func points(mm: Double, imageHeight: Double) -> Double { mm / 10 / waterHeightCM * imageHeight }
}

/// One air bubble drifting up through the water. Tiny ones stay round and rise straight; above
/// about 0.7 mm they flatten slightly, and larger ones sway gently from side to side.
struct BubbleState {
    var id: Int
    var x: Double, y: Double
    var originX: Double, originY: Double
    var age = 0.0
    /// Equivalent sphere diameter in millimetres.
    var diameter: Double
    /// Terminal rise speed in scene heights per second.
    var riseSpeed: Double
    /// Gentle side-to-side sway of larger bubbles: amplitude in scene widths, frequency in Hz.
    var zigzagAmplitude: Double
    var zigzagFrequency: Double
    var phase: Double
    /// Width over height; larger bubbles are squashed ellipsoids.
    var aspect: Double
    var depth: Double
    var sourceIndex: Int
}

/// Where bubbles come from: gas escaping now and then from a gap in the sand, or a plant leaf
/// releasing an occasional bubble of oxygen ("pearling"). Each lets go of one bubble at a time.
struct BubbleSource {
    enum Kind { case sand, plant }
    var kind: Kind
    var x: Double, y: Double
    var depth: Double
    /// Mean bubbles per second.
    var rate: Double
    /// Typical bubble diameter in millimetres.
    var medianSize: Double
    var nextIn: Double
    /// How far from its spot a bead may form, in centimetres (a fine fern leaflet allows little).
    var jitter = 0.08
}

/// A bead of oxygen growing on a leaf before it lets go ("pearling").
struct ClingingBubble {
    var x: Double, y: Double, depth: Double
    /// Full size in millimetres once it detaches.
    var diameter: Double
    var age = 0.0
    var duration: Double
    var sourceIndex: Int
}

/// A bubble that has reached the surface: it rests for a moment, flattened against the
/// surface film, then pops.
struct SurfacedBubble {
    var x: Double, y: Double, depth: Double, diameter: Double
    /// Where it was as it reached the film; it settles the last fraction of a millimetre from there.
    var arrivedAt: Double
    /// Its shape as it arrived; it flattens against the film from there.
    var arrivalAspect = 1.0
    var age = 0.0
    var life: Double
    static let pop = 0.15
}

/// One bubble as drawn this frame, whatever its stage.
struct BubbleDraw {
    var x: Double, y: Double, depth: Double
    /// Drawn diameter in millimetres.
    var diameter: Double
    var aspect: Double
    var alpha: Double
    enum Style { case rising, bead, reflection }
    /// A bead still growing on its leaf, or the mirror image of a bubble in the surface film.
    var style = Style.rising
    /// How far a bead on a leaf has grown (0–1).
    var grow = 1.0
}

struct BubbleField {
    static let maximumBubbles = 40
    /// Bubbles are drawn only a little larger than life, so a single one still catches the eye.
    static let displayScale = 1.15

    private(set) var bubbles: [BubbleState] = []
    private(set) var clinging: [ClingingBubble] = []
    private(set) var surfaced: [SurfacedBubble] = []
    private var visibleAtLastStep = SwimRegion(left: 0, right: 1, bottom: 0, top: 1)
    private(set) var sources: [BubbleSource] = []
    /// Where the water surface meets the far back of the scene, in scene heights.
    private var horizon = 0.75
    private(set) var released = 0
    private var dice: Dice

    init(seed: UInt64) { dice = Dice(seed: seed) }

    /// Rise speed in cm/s for a bubble of `mm` diameter. Real bubbles dart up at 10–20 cm/s; for a
    /// calm wallpaper they drift, taking fifteen to twenty seconds to cross the tank, larger ones faster.
    static func riseSpeedCM(diameter mm: Double) -> Double { 1.6 + 0.8 * mm }

    /// Sources on the open sand, spread across the bed at different depths, plus a few spots on
    /// the leafy plants of each scene.
    mutating func place(theme: AquariumTheme, visible: SwimRegion) {
        bubbles.removeAll()
        clinging.removeAll()
        surfaced.removeAll()
        sources.removeAll()
        switch theme {
        case .river: horizon = 0.76
        case .grove: horizon = 0.75
        case .spring: horizon = 0.72
        }
        let width = visible.right - visible.left
        for k in 0..<4 {
            let x = visible.left + width * (Double(k) + 0.5 + dice.value(-0.25...0.25)) / 4
            // Farther sources sit higher up the receding sand.
            let depth = [0.85, 1.05, 0.95, 1.12][k]
            sources.append(BubbleSource(kind: .sand, x: x, y: max(visible.bottom, 0.07 + (1.12 - depth) * 0.15),
                depth: depth, rate: 0.06, medianSize: 1.0, nextIn: dice.value(0...6)))
        }
        // Spots on leaves, checked on the artwork; `depth` matches how sharply the leaf is drawn.
        let leaves: [(x: Double, y: Double, depth: Double)]
        switch theme {
        case .grove: leaves = [(0.26, 0.33, 0.95), (0.36, 0.26, 0.95)]
        case .river: leaves = [(0.70, 0.30, 0.95), (0.614, 0.318, 0.95)]
        case .spring: leaves = [(0.22, 0.34, 0.95), (0.629, 0.43, 0.7)]
        }
        for leaf in leaves where (visible.left...visible.right).contains(leaf.x) {
            sources.append(BubbleSource(kind: .plant, x: leaf.x, y: leaf.y, depth: leaf.depth, rate: 0.07,
                medianSize: 1.2, nextIn: dice.value(0...8), jitter: leaf.depth < 0.8 ? 0 : 0.08))
        }
    }

    /// The water surface seen from below: a bubble farther back meets it lower on the screen.
    func surfaceY(depth: Double, visible: SwimRegion) -> Double {
        min(visible.top, horizon + 0.2 * ((depth - 0.5) / 0.9).clamped(to: 0...1))
    }

    /// A bubble's drawn height in scene heights.
    private func drawnHeight(_ diameter: Double, depth: Double, aspect: Double) -> Double {
        TankScale.height(cm: diameter / 10) * BubbleField.displayScale * ParticlePerspective.scale(depth) / pow(aspect, 2.0 / 3)
    }

    /// Everything to draw this frame: beads on leaves, rising bubbles, and bubbles at the surface.
    var drawn: [BubbleDraw] {
        var out: [BubbleDraw] = []
        for c in clinging {
            // A bead swells over its first few seconds on the leaf.
            let grow = min(1, 0.15 + c.age / (c.duration * 0.8))
            // In its last moments on the leaf it draws up into a neck before it lets go.
            // It stretches upward from the leaf, its base staying where it sits.
            let neck = max(0, (c.age - (c.duration - 0.3)) / 0.3)
            let diameter = c.diameter * pow(grow, 1.0 / 3), aspect = 1 - 0.15 * neck
            let lift = (drawnHeight(diameter, depth: c.depth, aspect: aspect) - drawnHeight(diameter, depth: c.depth, aspect: 1)) / 2
            out.append(BubbleDraw(x: c.x, y: c.y + lift, depth: c.depth, diameter: diameter, aspect: aspect,
                                  alpha: min(1, c.age / 1.2), style: .bead, grow: grow))
        }
        for b in bubbles {
            // A bead torn from a leaf wobbles for a moment as it lets go.
            let wobble = sources.indices.contains(b.sourceIndex) && sources[b.sourceIndex].kind == .plant
                ? 1 + 0.08 * exp(-b.age / 0.15) * sin(2 * .pi * 9 * b.age) : 1
            let rocking = b.zigzagAmplitude > 0 ? 1 + 0.05 * sin(4 * .pi * b.zigzagFrequency * b.age + b.phase) : 1
            let fadeIn = sources.indices.contains(b.sourceIndex) && sources[b.sourceIndex].kind == .plant ? 1 : min(1, b.age * 10)
            out.append(BubbleDraw(x: b.x, y: b.y, depth: b.depth, diameter: b.diameter, aspect: b.aspect * rocking * wobble, alpha: fadeIn))
            // Nearing the surface it meets its own reflection coming down to it.
            let surface = surfaceY(depth: b.depth, visible: visibleAtLastStep), film = TankScale.height(cm: 0.3)
            let gap = surface - b.y
            if gap < film {
                let height = drawnHeight(b.diameter, depth: b.depth, aspect: b.aspect)
                let near = max(0, 1 - gap / film)
                out.append(BubbleDraw(x: b.x, y: b.y + height * 0.78 + max(0, gap), depth: b.depth, diameter: b.diameter,
                                      aspect: b.aspect, alpha: 0.4 * near * near, style: .reflection))
            }
        }
        for s in surfaced {
            let popping = max(0, (s.age - (s.life - SurfacedBubble.pop)) / SurfacedBubble.pop)
            // Pressed against the surface film it flattens, touching its mirror image in the film.
            let y = s.y - (s.y - s.arrivedAt) * exp(-s.age / 0.1)
            let aspect = 1.3 - (1.3 - s.arrivalAspect) * exp(-s.age / 0.1)
            let height = drawnHeight(s.diameter, depth: s.depth, aspect: aspect)
            // Then it bursts: too small to leave a ring you could see, it just winks out.
            let size = 1 - 0.4 * popping, fade = 1 - popping
            out.append(BubbleDraw(x: s.x, y: y, depth: s.depth, diameter: s.diameter * size, aspect: aspect, alpha: fade))
            // The reflection carries on from where it was as the bubble rose, closing the last gap.
            let gap = max(0, s.y - y), near = max(0, 1 - gap / TankScale.height(cm: 0.3))
            out.append(BubbleDraw(x: s.x, y: y + height * 0.78 + gap, depth: s.depth, diameter: s.diameter * size, aspect: aspect,
                                  alpha: 0.4 * near * near * fade, style: .reflection))
        }
        return out
    }

    mutating func advance(_ dt: Double, visible: SwimRegion) {
        visibleAtLastStep = visible
        for i in bubbles.indices {
            bubbles[i].age += dt
            let b = bubbles[i]
            // A detaching bubble accelerates to terminal speed within a few tenths of a second.
            let free = b.originY + b.riseSpeed * (b.age - 0.12 * (1 - exp(-b.age / 0.12)))
            // Over its last few millimetres a bubble slows as it presses up into the surface film.
            let surface = surfaceY(depth: b.depth, visible: visible), film = TankScale.height(cm: 0.3)
            bubbles[i].y = surface - free > film ? free : surface - film * exp(-(film - (surface - free)) / film)
            // The sway builds up over the first couple of centimetres of rise.
            let risen = bubbles[i].y - b.originY
            let onset = 1 - exp(-risen / TankScale.height(cm: 2))
            bubbles[i].x = b.originX + b.zigzagAmplitude * onset * sin(2 * .pi * b.zigzagFrequency * b.age + b.phase)
        }
        // Bubbles reaching the surface rest there a moment, then pop.
        for i in surfaced.indices { surfaced[i].age += dt }
        surfaced.removeAll { $0.age >= $0.life }
        let arrived = bubbles.filter { $0.y >= surfaceY(depth: $0.depth, visible: visible) - TankScale.height(cm: 0.3) * 0.2 }
        for b in arrived {
            surfaced.append(SurfacedBubble(x: b.x, y: surfaceY(depth: b.depth, visible: visible), depth: b.depth,
                                           diameter: b.diameter, arrivedAt: b.y, arrivalAspect: b.aspect, life: dice.value(0.6...1.5)))
        }
        let arrivedIDs = Set(arrived.map(\.id))
        bubbles.removeAll { arrivedIDs.contains($0.id) }
        // Beads on leaves grow, then let go; the leaf's next bead starts only once this one has left.
        for i in clinging.indices { clinging[i].age += dt }
        for c in clinging where c.age >= c.duration {
            if bubbles.count < Self.maximumBubbles {
                released += 1
                bubbles.append(rising(id: released, x: c.x, y: c.y, diameter: c.diameter, depth: c.depth, sourceIndex: c.sourceIndex))
            }
            sources[c.sourceIndex].nextIn = 1.5 + dice.exponential(mean: 1 / sources[c.sourceIndex].rate)
        }
        clinging.removeAll { $0.age >= $0.duration }
        for i in sources.indices {
            if sources[i].kind == .plant && clinging.contains(where: { $0.sourceIndex == i }) { continue }
            sources[i].nextIn -= dt
            while sources[i].nextIn <= 0 {
                // One bubble at a time, at random moments (exponential gaps).
                let source = sources[i]
                let gap = 1.5 + dice.exponential(mean: 1 / source.rate)
                sources[i].nextIn += gap
                if source.kind == .plant {
                    // A leaf grows a bead for several seconds before it lets go.
                    // The bead forms right on the leaf.
                    let d = dice.logNormal(median: source.medianSize, spread: 0.2).clamped(to: 0.9...1.4)
                    clinging.append(ClingingBubble(x: source.x + TankScale.width(cm: dice.normal(deviation: source.jitter)), y: source.y,
                        depth: (source.depth + dice.normal(deviation: 0.02)).clamped(to: 0.5...1.4), diameter: d,
                        duration: dice.value(4...9), sourceIndex: i))
                    break
                }
                if bubbles.count < Self.maximumBubbles { bubbles.append(release(from: source, index: i, visible: visible)) }
            }
        }
    }

    private mutating func release(from source: BubbleSource, index: Int, visible: SwimRegion) -> BubbleState {
        released += 1
        let diameter: Double
        var x = source.x; let y = source.y
        switch source.kind {
        case .sand:
            diameter = dice.logNormal(median: source.medianSize, spread: 0.3).clamped(to: 0.6...1.7)
            x += TankScale.width(cm: dice.normal(deviation: 1.5))
        case .plant:
            diameter = dice.logNormal(median: source.medianSize, spread: 0.25).clamped(to: 0.5...1.3)
            x += TankScale.width(cm: dice.normal(deviation: 0.8))
        }
        x = min(visible.right, max(visible.left, x))
        let depth = (source.depth + dice.normal(deviation: 0.04)).clamped(to: 0.5...1.4)
        return rising(id: released, x: x, y: y, diameter: diameter, depth: depth, sourceIndex: index)
    }

    private mutating func rising(id: Int, x: Double, y: Double, diameter: Double, depth: Double, sourceIndex index: Int) -> BubbleState {
        // Larger bubbles sway slowly from side to side as they drift up.
        let zigzag = diameter > 1.4 ? TankScale.width(cm: min(0.3, (diameter - 1.4) * 0.12 + 0.08)) : 0
        return BubbleState(id: id, x: x, y: y, originX: x, originY: y,
            diameter: diameter,
            riseSpeed: TankScale.height(cm: Self.riseSpeedCM(diameter: diameter)),
            zigzagAmplitude: zigzag, zigzagFrequency: dice.value(0.3...0.6), phase: dice.value(0...(2 * .pi)),
            aspect: 1 + min(0.55, max(0, diameter - 0.7) * 0.14), depth: depth, sourceIndex: index)
    }
}
