import Foundation

/// A seeded dice owned by one individual (a fish, a bubble, a pellet), so each has its own
/// independent stream of chance that can be replayed exactly in tests.
///
/// Generator: xoshiro256** (Blackman & Vigna), seeded through SplitMix64. It is fast,
/// passes the standard statistical batteries, and neighbouring seeds give unrelated streams.
/// The shaped draws turn it into the distributions real animal movement follows: waiting
/// times between decisions are exponential, turn sizes and speeds cluster around a typical
/// value with a normal or log-normal spread.
struct Dice: Equatable {
    private var s0: UInt64, s1: UInt64, s2: UInt64, s3: UInt64

    init(seed: UInt64) {
        var mix = seed
        func splitMix() -> UInt64 {
            mix &+= 0x9E3779B97F4A7C15
            var z = mix
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        s0 = splitMix(); s1 = splitMix(); s2 = splitMix(); s3 = splitMix()
    }

    /// Identifies the current position in the stream; equal dice produce equal futures.
    var fingerprint: UInt64 { s0 ^ (s1 &* 3) ^ (s2 &* 5) ^ (s3 &* 7) }

    private static func rotate(_ x: UInt64, _ k: UInt64) -> UInt64 { (x << k) | (x >> (64 - k)) }

    mutating func nextBits() -> UInt64 {
        let result = Self.rotate(s1 &* 5, 7) &* 9
        let t = s1 << 17
        s2 ^= s0; s3 ^= s1; s1 ^= s2; s0 ^= s3
        s2 ^= t
        s3 = Self.rotate(s3, 45)
        return result
    }

    /// Uniform in [0, 1).
    mutating func next() -> Double { Double(nextBits() >> 11) * 0x1.0p-53 }

    /// Uniform within `range`.
    mutating func value(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + next() * (range.upperBound - range.lowerBound)
    }

    /// True with probability `p`.
    mutating func chance(_ p: Double) -> Bool { next() < p }

    /// -1 or +1 with equal odds.
    mutating func sign() -> Double { chance(0.5) ? -1 : 1 }

    /// Normally distributed (Box–Muller).
    mutating func normal(mean: Double = 0, deviation: Double) -> Double {
        let u = max(next(), .leastNonzeroMagnitude), v = next()
        return mean + deviation * sqrt(-2 * log(u)) * cos(2 * .pi * v)
    }

    /// Exponentially distributed waiting time: the gap between events that happen at random
    /// with a constant rate. Most waits are short, a few are long.
    mutating func exponential(mean: Double) -> Double { -mean * log(1 - next()) }

    /// Positive and right-skewed around `median`; `spread` is the deviation of its logarithm.
    mutating func logNormal(median: Double, spread: Double) -> Double { median * exp(normal(deviation: spread)) }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(range.upperBound, max(range.lowerBound, self)) }
}
