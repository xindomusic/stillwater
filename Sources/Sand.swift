import Foundation

/// A sand grain or a faint cloud of fine silt, kicked up where a resident touches the bed.
struct SandGrain {
    var x: Double, y: Double
    var vx: Double, vy: Double
    /// Height of the bed where the grain settles.
    var floor: Double
    var age = 0.0
    var life: Double
    /// Diameter in millimetres (a cloud's is its spread).
    var size: Double
    var depth: Double
    var isCloud: Bool
}

/// Sand stirred up by residents: loaches sifting, crabs scuttling, shrimp picking, and fish
/// taking food off the bottom. Grains are thrown up, slowed by the water, and sink back; the
/// finest silt hangs as a soft cloud and fades.
struct SandField {
    static let maximumGrains = 240

    private(set) var grains: [SandGrain] = []
    private(set) var puffs = 0
    private var dice: Dice

    init(seed: UInt64) { dice = Dice(seed: seed) }

    /// Kicks up sand at a point on the bed. `strength` 1 is a fish nosing into the sand for
    /// food; smaller values are a shrimp's pick or a crab's footfall.
    mutating func puff(x: Double, floor: Double, depth: Double, strength: Double) {
        puffs += 1
        let count = Int((9 + 21 * strength) * dice.value(0.7...1.3))
        for _ in 0..<count where grains.count < Self.maximumGrains {
            // A puff throws grains up and out; stronger digs throw them higher.
            let angle = dice.normal(mean: .pi / 2, deviation: 0.45)
            let speed = TankScale.height(cm: strength > 0.25 ? dice.value(3...7) : dice.value(1.5...4))
            grains.append(SandGrain(x: x + TankScale.width(cm: dice.normal(deviation: 0.3)), y: floor,
                vx: cos(angle) * speed / TankScale.aspect, vy: sin(angle) * speed, floor: floor,
                life: dice.value(1.2...2.4), size: dice.value(0.35...0.8),
                depth: (depth + dice.normal(deviation: 0.03)).clamped(to: 0.5...1.4), isCloud: false))
        }
        if strength > 0.25 && grains.count < Self.maximumGrains {
            grains.append(SandGrain(x: x, y: floor + TankScale.height(cm: 0.3), vx: TankScale.width(cm: dice.normal(deviation: 0.3)),
                vy: TankScale.height(cm: 0.6), floor: floor, life: dice.value(2...3.5),
                size: 6 + 8 * strength, depth: depth, isCloud: true))
        }
    }

    /// Rolls the sand's own dice, so stirring sand never changes a resident's choices.
    mutating func chance(_ p: Double) -> Bool { dice.chance(p) }

    mutating func advance(_ dt: Double) {
        let drag = exp(-dt * 4)
        let settling = TankScale.height(cm: 7) * dt
        for i in grains.indices {
            grains[i].age += dt
            grains[i].x += grains[i].vx * dt
            grains[i].y += grains[i].vy * dt
            if grains[i].isCloud {
                grains[i].vx *= exp(-dt * 1.5)
                grains[i].vy *= exp(-dt * 1.5)
                continue
            }
            grains[i].vx *= drag
            grains[i].vy = grains[i].vy * drag - settling
            if grains[i].y <= grains[i].floor {
                grains[i].y = grains[i].floor
                grains[i].vx = 0
                grains[i].vy = 0
            }
        }
        grains.removeAll { $0.age >= $0.life }
    }

    /// Visibility: grains fade as they settle back into the bed, clouds as they disperse.
    static func opacity(of grain: SandGrain) -> Double {
        let fadeIn = min(1, grain.age * 8)
        let fadeOut = min(1, (grain.life - grain.age) / (grain.isCloud ? 1.5 : 0.5))
        return max(0, fadeIn * fadeOut) * (grain.isCloud ? 0.6 : 0.95)
    }
}
