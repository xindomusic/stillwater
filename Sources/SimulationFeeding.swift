import Foundation

// Feeding: dropping pellets, noticing food, and eating.
// Split out of Simulation.swift; members used here are internal rather than
// private so this extension can live in its own file (single-module app).
extension AquariumSimulation {
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

    /// Three sprinkle positions, spread apart and away from the previous feeding.
    mutating func sprinkleSources(in r: SwimRegion, near residents: [FishState]) -> [Double] {
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

    mutating func advanceFood(_ dt: Double) {
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

    /// A hungry fish picks the nearest pellet in view, preferring ones fewer others are chasing.
    func noticeFood(_ f: inout FishState, home: SwimRegion, claims: [Int: Int]) {
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

    /// A crab heading for food with another crab already between it and the food, close by.
    func isQueuedBehind(_ f: FishState, food: FeedingResponse) -> Bool {
        let mine = hypot(food.x - f.x, food.y - f.y)
        return neighbors.contains { other in
            other.id != f.id && other.species == .crab
                && hypot(food.x - other.x, food.y - other.y) < mine
                && hypot(other.x - f.x, (other.y - f.y) * 0.5) < f.species.bedFootprint * f.depth * 1.1
        }
    }

    /// A loach settling down to rest goes to lie at the foot of a nearby rock, or alongside another
    /// resting loach (kuhli loaches rest together), and crawls there before it settles.

    mutating func eatIfReached(_ f: inout FishState, targetFood: Int?) {
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
