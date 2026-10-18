import Foundation
import CoreGraphics

// Scripted anglers fish the deterministic simulation and report what happened, so balance and
// realism can be judged without a screen: `zsh tools/fishing-transcript.sh [minutes] [--story]`.

struct Angler {
    enum Style: String { case skilled, reelsNonstop = "reels nonstop", neverReels = "never reels", impatient = "strikes at nibbles" }
    var style: Style
    var strikeAt: Double?
    var reelClock = 0.0
    var dice = Dice(seed: 99)
}

struct Tally {
    var casts = 0, interest = 0, refused = 0, nibbles = 0, takes = 0, hooked = 0, landed = 0
    var missed = 0, spat = 0, snapped = 0, straightened = 0, thrown = 0, stolen = 0, spooked = 0, follows = 0
    var bySpecies: [FishSpecies: Int] = [:]
    var fightSeconds: [Double] = []
    var thieves: [FishSpecies: Int] = [:]
}

@MainActor func session(hook: HookKind, offering: Offering, style: Angler.Style, minutes: Double, counts: [FishSpecies: Int],
                        theme: AquariumTheme = .river, seed: UInt64 = 7, story: Bool = false) -> Tally {
    var config = AquariumConfiguration()
    config.theme = theme
    config.counts = Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map { ($0.rawValue, counts[$0] ?? 0) })
    var sim = AquariumSimulation(seed: seed)
    sim.visibleRegion = AquariumFraming(viewport: CGSize(width: 1600, height: 900), image: CGSize(width: 1935, height: 812)).visibleRegion
    sim.synchronize(config)
    sim.startFishing(hook: hook, offering: offering)
    var angler = Angler(style: style)
    var tally = Tally()
    let dt = 1.0 / 30
    var t = 0.0
    var fightStart = 0.0
    var castNumber = 0
    while t < minutes * 60 {
        t += dt
        guard let rig = sim.rig else { break }
        switch rig.phase {
        case .stowed:
            // Cast near the middle of the swimmers (or onto the bed for bottom rigs), varying the spot.
            castNumber += 1
            let bottom = offering == .softWorm || (!offering.isLure && castNumber % 3 == 0)
            let x = bottom ? angler.dice.value(0.2...0.55) : angler.dice.value(0.3...0.65)
            let y = bottom ? 0.1 : angler.dice.value(0.4...0.65)
            sim.cast(x: x, y: y)
        case .sinking, .fishing:
            if let at = angler.strikeAt, t >= at { sim.strike(); angler.strikeAt = nil }
            if offering.isLure {
                // Retrieve in pulls with pauses and the odd twitch; a fly mostly sits and twitches.
                // Count the lure down for a few seconds before starting the retrieve.
                if offering != .dryFly && rig.soak < 1.5 && rig.phase == .sinking { sim.setReeling(false); break }
                angler.reelClock += dt
                let cycle = angler.reelClock.truncatingRemainder(dividingBy: offering == .dryFly ? 6 : 2.2)
                sim.setReeling(offering == .dryFly ? cycle > 5.6 : cycle < 1.5)
                if angler.dice.chance(dt * 0.25) && angler.strikeAt == nil && rig.holderID == nil { sim.strike() }
            } else {
                sim.setReeling(false)
                // Bare hook, or nothing for a long while: reel in and cast again.
                if rig.baitLeft <= 0.04 || rig.soak > 45 { sim.reelIn() }
            }
        case .fighting:
            switch style {
            case .skilled, .impatient: sim.setReeling(!rig.running && rig.pressure < rig.hook.strength * 0.8)
            case .reelsNonstop: sim.setReeling(true)
            case .neverReels: sim.setReeling(false)
            }
        default:
            sim.setReeling(false)
        }
        sim.step(delta: dt, configuration: config)
        for event in sim.drainFishingEvents() {
            if story { print(String(format: "%7.2fs  ", t) + "\(event)".replacingOccurrences(of: "main.FishSpecies.", with: "")) }
            switch event {
            case .cast: tally.casts += 1
            case .interest, .curious: tally.interest += 1
            case .following: tally.follows += 1; tally.interest += 1
            case .refused: tally.refused += 1
            case .nibble:
                tally.nibbles += 1
                if style == .impatient && angler.strikeAt == nil { angler.strikeAt = t + 0.25 }
            case .take:
                tally.takes += 1
                // A human sees the float go and lifts after a quarter of a second or so.
                if !hook.setsItself || style == .impatient { angler.strikeAt = t + angler.dice.value(0.18...0.4) }
            case .missed: tally.missed += 1
            case .spat: tally.spat += 1
            case .hooked(let s): tally.hooked += 1; fightStart = t; _ = s; angler.strikeAt = nil
            case .landed(let record):
                tally.landed += 1
                tally.bySpecies[record.species, default: 0] += 1
                tally.fightSeconds.append(t - fightStart)
            case .lineSnapped: tally.snapped += 1
            case .hookStraightened: tally.straightened += 1
            case .hookPulled: tally.snapped += 1
            case .threwHook: tally.thrown += 1
            case .baitStolen(let s): tally.stolen += 1; tally.thieves[s, default: 0] += 1
            case .spooked: tally.spooked += 1
            default: break
            }
        }
    }
    return tally
}

func describe(_ t: Tally, minutes: Double) -> String {
    let fights = t.fightSeconds.isEmpty ? "-" : String(format: "%.0fs", t.fightSeconds.reduce(0, +) / Double(t.fightSeconds.count))
    let species = t.bySpecies.sorted { $0.value > $1.value }.map { "\($0.key.rawValue)×\($0.value)" }.joined(separator: " ")
    let thieves = t.thieves.sorted { $0.value > $1.value }.map { "\($0.key.rawValue)×\($0.value)" }.joined(separator: " ")
    return String(format: "landed %2d (%.1f/min) | casts %3d interest %3d refused %3d nibbles %4d takes %3d hooked %2d | missed %2d spat %2d snapped %d straightened %d thrown %d | stolen %2d spooked %3d | fight %@",
                  t.landed, Double(t.landed) / minutes, t.casts, t.interest, t.refused, t.nibbles, t.takes, t.hooked,
                  t.missed, t.spat, t.snapped, t.straightened, t.thrown, t.stolen, t.spooked, fights)
        + (species.isEmpty ? "" : "\n      caught: \(species)") + (thieves.isEmpty ? "" : "\n      bait thieves: \(thieves)")
}

@main struct FishingTranscript {
    @MainActor static func main() {
        let arguments = CommandLine.arguments.dropFirst()
        let minutes = arguments.compactMap(Double.init).first ?? 5
        let story = arguments.contains("--story")
        let community: [FishSpecies: Int] = [.rasbora: 5, .cherry: 3, .pearl: 1, .loach: 2, .danio: 5, .golden: 3, .betta: 1, .koi: 1, .shrimp: 4, .crab: 2]
        if story {
            print("== Story: J-hook and bloodworm, skilled angler, colourful community ==")
            _ = session(hook: .jHook, offering: .bloodworm, style: .skilled, minutes: min(minutes, 3), counts: community, story: true)
            print("\n== Story: circle hook and bread, skilled angler ==")
            _ = session(hook: .circle, offering: .bread, style: .skilled, minutes: min(minutes, 3), counts: community, story: true)
            print("\n== Story: fine hook and dry fly ==")
            _ = session(hook: .fine, offering: .dryFly, style: .skilled, minutes: min(minutes, 2), counts: community, story: true)
            print("\n== Story: J-hook and spinner ==")
            _ = session(hook: .jHook, offering: .spinner, style: .skilled, minutes: min(minutes, 2), counts: community, story: true)
            return
        }
        print("Scripted anglers, \(Int(minutes)) simulated minutes each, colourful community (27 residents), Riverlight\n")
        for hook in HookKind.allCases {
            for offering in Offering.allCases {
                let t = session(hook: hook, offering: offering, style: .skilled, minutes: minutes, counts: community)
                print("\(hook.shortTitle.padding(toLength: 11, withPad: " ", startingAt: 0)) \(offering.title.padding(toLength: 14, withPad: " ", startingAt: 0)) \(describe(t, minutes: minutes))")
            }
        }
        print("\nFight technique, J-hook and bread (koi and barbs take it):")
        for style in [Angler.Style.skilled, .reelsNonstop, .neverReels, .impatient] {
            let t = session(hook: .jHook, offering: .bread, style: style, minutes: minutes, counts: community)
            print("  \(style.rawValue.padding(toLength: 19, withPad: " ", startingAt: 0)) \(describe(t, minutes: minutes))")
        }
        print("\nDefault tank (12 rasboras, 8 cherry barbs, 2 gouramis, 4 loaches), J-hook and bloodworm:")
        let t = session(hook: .jHook, offering: .bloodworm, style: .skilled, minutes: minutes, counts: [.rasbora: 12, .cherry: 8, .pearl: 2, .loach: 4])
        print("  \(describe(t, minutes: minutes))")
        print("\nKoi only (3), each hook with bread:")
        for hook in HookKind.allCases {
            let t = session(hook: hook, offering: .bread, style: .skilled, minutes: minutes * 3, counts: [.koi: 3])
            print("  \(hook.shortTitle.padding(toLength: 11, withPad: " ", startingAt: 0)) \(describe(t, minutes: minutes))")
        }
    }
}
