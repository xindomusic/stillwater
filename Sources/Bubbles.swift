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

/// One rising air bubble. Sizes and speeds follow measured air bubbles in water: tiny ones
/// rise slowly and straight and stay round; above about 0.7 mm they flatten, and above about
/// 1.4 mm they rock and zigzag.
struct BubbleState {
    var id: Int
    var x: Double, y: Double
    var originX: Double, originY: Double
    var age = 0.0
    /// Equivalent sphere diameter in millimetres.
    var diameter: Double
    /// Terminal rise speed in scene heights per second.
    var riseSpeed: Double
    /// Side-to-side zigzag of larger bubbles: amplitude in scene widths, frequency in Hz.
    var zigzagAmplitude: Double
    var zigzagFrequency: Double
    var phase: Double
    /// Width over height; larger bubbles are squashed ellipsoids.
    var aspect: Double
    var depth: Double
    var sourceIndex: Int
}

/// Where bubbles come from: an air stone releasing a steady stream near the bed, or plant
/// leaves releasing an occasional tiny bubble of oxygen ("pearling").
struct BubbleSource {
    enum Kind { case airStone, plant }
    var kind: Kind
    var x: Double, y: Double
    var depth: Double
    /// Mean bubbles per second.
    var rate: Double
    /// Typical bubble diameter in millimetres.
    var medianSize: Double
    var nextIn: Double
}

struct BubbleField {
    static let maximumBubbles = 260
    /// Bubbles are drawn a little larger than life so a stream reads clearly at desktop size.
    static let displayScale = 1.3

    private(set) var bubbles: [BubbleState] = []
    private(set) var sources: [BubbleSource] = []
    private(set) var released = 0
    private var dice: Dice

    init(seed: UInt64) { dice = Dice(seed: seed) }

    /// Rise speed in cm/s for a bubble of `mm` diameter, fitted to measurements in ordinary
    /// (slightly contaminated) water: about 12 cm/s at 1 mm, levelling off near 22 cm/s.
    static func riseSpeedCM(diameter mm: Double) -> Double { 23 * (1 - exp(-mm / 1.3)) }

    /// Sources for a theme, kept inside the visible part of the scene.
    mutating func place(theme: AquariumTheme, visible: SwimRegion) {
        bubbles.removeAll()
        // A main stream from a medium air stone and a fainter one farther back.
        let stones: [(x: Double, depth: Double, rate: Double, size: Double)]
        switch theme {
        // Stones sit on open sand beside the rocks, clear of the beds where crabs and loaches forage.
        case .grove: stones = [(0.42, 1.08, 60, 3.0), (0.33, 0.90, 25, 3.0)]
        case .river: stones = [(0.70, 1.08, 60, 3.0), (0.78, 0.90, 25, 3.0)]
        case .spring: stones = [(0.64, 1.08, 60, 3.0), (0.72, 0.90, 25, 3.0)]
        }
        sources = stones.map { stone in
            let x = min(visible.right - 0.02, max(visible.left + 0.02, stone.x))
            return BubbleSource(kind: .airStone, x: x, y: max(visible.bottom, 0.07), depth: stone.depth, rate: stone.rate, medianSize: stone.size, nextIn: 0)
        }
        // Plant leaves along both sides of the scene.
        for side in [0.08, 0.92] {
            let x = min(visible.right - 0.03, max(visible.left + 0.03, side))
            sources.append(BubbleSource(kind: .plant, x: x, y: 0.25, depth: 1.0, rate: 0.35, medianSize: 1.0, nextIn: 0))
        }
    }

    mutating func advance(_ dt: Double, visible: SwimRegion) {
        for i in bubbles.indices {
            bubbles[i].age += dt
            let b = bubbles[i]
            // A detaching bubble accelerates to terminal speed within a few tenths of a second.
            bubbles[i].y = b.originY + b.riseSpeed * (b.age - 0.12 * (1 - exp(-b.age / 0.12)))
            // Path instability grows over the first couple of centimetres of rise.
            let risen = bubbles[i].y - b.originY
            let onset = 1 - exp(-risen / TankScale.height(cm: 2))
            bubbles[i].x = b.originX + b.zigzagAmplitude * onset * sin(2 * .pi * b.zigzagFrequency * b.age + b.phase)
        }
        bubbles.removeAll { $0.y >= visible.top }
        for i in sources.indices {
            sources[i].nextIn -= dt
            while sources[i].nextIn <= 0 {
                // Release times are random events (exponential gaps), a little regularized for stones.
                let source = sources[i]
                let gap = source.kind == .airStone
                    ? 0.5 / source.rate + dice.exponential(mean: 0.5 / source.rate)
                    : dice.exponential(mean: 1 / source.rate)
                sources[i].nextIn += gap
                if bubbles.count < Self.maximumBubbles { bubbles.append(release(from: source, index: i, visible: visible)) }
            }
        }
    }

    private mutating func release(from source: BubbleSource, index: Int, visible: SwimRegion) -> BubbleState {
        released += 1
        let diameter: Double
        var x = source.x, y = source.y
        switch source.kind {
        case .airStone:
            // Stones release mostly millimetre-scale bubbles plus a fine mist of tiny ones.
            diameter = dice.chance(0.45)
                ? dice.logNormal(median: 0.8, spread: 0.25).clamped(to: 0.4...1.2)
                : dice.logNormal(median: source.medianSize, spread: 0.3).clamped(to: 1...6)
            // Bubbles leave from pores all along the 2 cm stone, so they rarely stack into chains.
            x += TankScale.width(cm: dice.value(-0.9...0.9))
        case .plant:
            diameter = dice.logNormal(median: source.medianSize, spread: 0.25).clamped(to: 0.5...1.6)
            x += TankScale.width(cm: dice.normal(deviation: 2.5))
            y += dice.value(0...0.25)
        }
        x = min(visible.right, max(visible.left, x))
        let depth = (source.depth + dice.normal(deviation: 0.04)).clamped(to: 0.5...1.4)
        // Paths turn unstable above about 1.4 mm: the bubble zigzags and rocks.
        let zigzag = diameter > 1.4 ? TankScale.width(cm: min(0.25, (diameter - 1.4) * 0.09 + 0.04)) : 0
        return BubbleState(id: released, x: x, y: y, originX: x, originY: y,
            diameter: diameter,
            riseSpeed: TankScale.height(cm: Self.riseSpeedCM(diameter: diameter)),
            zigzagAmplitude: zigzag, zigzagFrequency: dice.value(4...7), phase: dice.value(0...(2 * .pi)),
            aspect: 1 + min(0.55, max(0, diameter - 0.7) * 0.14), depth: depth, sourceIndex: index)
    }
}
