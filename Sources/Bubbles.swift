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
}

struct BubbleField {
    static let maximumBubbles = 40
    /// Bubbles are drawn a little larger than life so single bubbles read at desktop size.
    static let displayScale = 2.0

    private(set) var bubbles: [BubbleState] = []
    private(set) var sources: [BubbleSource] = []
    private(set) var released = 0
    private var dice: Dice

    init(seed: UInt64) { dice = Dice(seed: seed) }

    /// Rise speed in cm/s for a bubble of `mm` diameter. Real bubbles dart up at 10–20 cm/s; for a
    /// calm wallpaper they drift, taking seven to ten seconds to cross the tank, larger ones faster.
    static func riseSpeedCM(diameter mm: Double) -> Double { 2 + 0.9 * mm }

    /// Sources on the open sand, spread across the bed at different depths, plus a few spots on
    /// the leafy plants of each scene.
    mutating func place(theme: AquariumTheme, visible: SwimRegion) {
        bubbles.removeAll()
        sources.removeAll()
        let width = visible.right - visible.left
        for k in 0..<4 {
            let x = visible.left + width * (Double(k) + 0.5 + dice.value(-0.25...0.25)) / 4
            // Farther sources sit higher up the receding sand.
            let depth = [0.85, 1.05, 0.95, 1.12][k]
            sources.append(BubbleSource(kind: .sand, x: x, y: max(visible.bottom, 0.07 + (1.12 - depth) * 0.15),
                depth: depth, rate: 0.2, medianSize: 2.4, nextIn: dice.value(0...6)))
        }
        let leaves: [(x: Double, y: Double)]
        switch theme {
        case .grove: leaves = [(0.26, 0.33), (0.36, 0.26)]
        case .river: leaves = [(0.74, 0.27), (0.66, 0.21)]
        case .spring: leaves = [(0.24, 0.30), (0.74, 0.32)]
        }
        for leaf in leaves where (visible.left...visible.right).contains(leaf.x) {
            sources.append(BubbleSource(kind: .plant, x: leaf.x, y: leaf.y, depth: 0.95, rate: 0.12,
                medianSize: 1.6, nextIn: dice.value(0...8)))
        }
    }

    mutating func advance(_ dt: Double, visible: SwimRegion) {
        for i in bubbles.indices {
            bubbles[i].age += dt
            let b = bubbles[i]
            // A detaching bubble accelerates to terminal speed within a few tenths of a second.
            bubbles[i].y = b.originY + b.riseSpeed * (b.age - 0.12 * (1 - exp(-b.age / 0.12)))
            // The sway builds up over the first couple of centimetres of rise.
            let risen = bubbles[i].y - b.originY
            let onset = 1 - exp(-risen / TankScale.height(cm: 2))
            bubbles[i].x = b.originX + b.zigzagAmplitude * onset * sin(2 * .pi * b.zigzagFrequency * b.age + b.phase)
        }
        bubbles.removeAll { $0.y >= visible.top }
        for i in sources.indices {
            sources[i].nextIn -= dt
            while sources[i].nextIn <= 0 {
                // One bubble at a time, at random moments (exponential gaps).
                let source = sources[i]
                let gap = 1.5 + dice.exponential(mean: 1 / source.rate)
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
        case .sand:
            diameter = dice.logNormal(median: source.medianSize, spread: 0.35).clamped(to: 0.6...3.6)
            x += TankScale.width(cm: dice.normal(deviation: 1.5))
        case .plant:
            diameter = dice.logNormal(median: source.medianSize, spread: 0.25).clamped(to: 0.5...1.6)
            x += TankScale.width(cm: dice.normal(deviation: 0.8))
        }
        x = min(visible.right, max(visible.left, x))
        let depth = (source.depth + dice.normal(deviation: 0.04)).clamped(to: 0.5...1.4)
        // Larger bubbles sway slowly from side to side as they drift up.
        let zigzag = diameter > 1.4 ? TankScale.width(cm: min(0.5, (diameter - 1.4) * 0.16 + 0.12)) : 0
        return BubbleState(id: released, x: x, y: y, originX: x, originY: y,
            diameter: diameter,
            riseSpeed: TankScale.height(cm: Self.riseSpeedCM(diameter: diameter)),
            zigzagAmplitude: zigzag, zigzagFrequency: dice.value(0.5...1.0), phase: dice.value(0...(2 * .pi)),
            aspect: 1 + min(0.55, max(0, diameter - 0.7) * 0.14), depth: depth, sourceIndex: index)
    }
}
