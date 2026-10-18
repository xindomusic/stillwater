import AppKit
import SwiftUI
import Combine

// The fishing window: the aquarium with a line in it. Click the water to cast there, click to
// strike, hold to reel. Readouts show what the fish are doing, how hard the line is pulling,
// and each catch before it goes back.

struct CatchCard: Equatable {
    var record: CatchRecord
    var personalBest: Bool
    var firstOfSpecies: Bool
}

@MainActor final class FishingSession: ObservableObject {
    @Published var status = "Click anywhere in the water to cast there."
    @Published var phase: RigPhase = .stowed
    /// Line pressure as a share of what the hook holds (1 = about to give).
    @Published var tension = 0.0
    @Published var slack = false
    @Published var baitLeft = 1.0
    @Published var lineOutCM = 0
    @Published var strikeNow = false
    @Published var running = false
    @Published var diving = false
    @Published var card: CatchCard?
    @Published var blocked: String?
    @Published var advice: String?
    fileprivate var priority = 0
    fileprivate var spokenAt = Date.distantPast
    fileprivate var cardShownAt = Date.distantPast

    /// More important news replaces less important news at once; otherwise each line stays a
    /// moment. An outcome (missed, spat, hooked, lost, landed) always shows: it answers a prompt.
    func say(_ text: String, priority: Int, outcome: Bool = false) {
        let now = Date()
        guard outcome || priority >= self.priority || now.timeIntervalSince(spokenAt) > 1.6 else { return }
        if status != text { status = text }
        self.priority = priority
        spokenAt = now
    }
}

/// Clicks on the water go to the angler, not to SpriteKit.
final class FishingInputView: NSView {
    weak var controller: FishingController?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        controller?.press(at: convert(event.locationInWindow, from: nil))
    }
    override func mouseUp(with event: NSEvent) { controller?.release() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
}

/// Readouts drawn over the water that never take a click.
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor final class FishingController: NSObject, NSWindowDelegate {
    static let toolbarHeight: CGFloat = 66
    let store: AquariumStore
    let session = FishingSession()
    let window: NSWindow
    let surface: AquariumSurface
    private let input: FishingInputView
    private var keyMonitor: Any?
    private var pressing = false
    private var heldToReel = false
    private var pressGeneration = 0
    private var subscriptions: Set<AnyCancellable> = []
    var onClose: (() -> Void)?
    /// Hidden, minimized, or covered windows pause their renderer like every other surface.
    var onVisibilityChange: (() -> Void)?

    init(store: AquariumStore) {
        self.store = store
        let size = NSSize(width: 1200, height: 740)
        let water = NSRect(x: 0, y: Self.toolbarHeight, width: size.width, height: size.height - Self.toolbarHeight)
        surface = AquariumSurface(frame: water, configuration: store.configuration)
        surface.autoresizingMask = [.width, .height]
        input = FishingInputView(frame: water)
        input.autoresizingMask = [.width, .height]
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.addSubview(surface)
        container.addSubview(input)
        let overlay = PassThroughHostingView(rootView: FishingOverlay(session: session))
        overlay.frame = water
        overlay.autoresizingMask = [.width, .height]
        container.addSubview(overlay)
        let toolbar = NSHostingView(rootView: FishingToolbar(store: store, session: session, reelIn: { [weak self] in self?.reelIn() }))
        toolbar.frame = NSRect(x: 0, y: 0, width: size.width, height: Self.toolbarHeight)
        toolbar.autoresizingMask = [.width, .maxYMargin]
        container.addSubview(toolbar)
        input.controller = self
        window.title = "Stillwater · Fishing"
        window.contentView = container
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 860, height: 520)
        window.delegate = self
        window.center()
        surface.aquarium.startFishing(hook: store.angling.hook, offering: store.angling.offering)
        surface.aquarium.afterFishingStep = { [weak self] in self?.refresh() }
        store.$angling.map { [$0.hook.rawValue, $0.offering.rawValue] }.removeDuplicates().dropFirst().sink { [weak self] _ in
            guard let self else { return }
            self.surface.aquarium.changeTackle(hook: self.store.angling.hook, offering: self.store.angling.offering)
            self.refreshAdvice()
            self.session.say("Tied on a \(self.store.angling.hook.title.lowercased()) with \(Self.article(self.store.angling.offering)). Click the water to cast.", priority: 1)
        }.store(in: &subscriptions)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return consumed ? nil : event
        }
        refreshAvailability()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(input)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidChangeOcclusionState(_ notification: Notification) { onVisibilityChange?() }
    func windowDidMiniaturize(_ notification: Notification) { onVisibilityChange?() }
    func windowDidDeminiaturize(_ notification: Notification) { onVisibilityChange?() }

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        surface.aquarium.afterFishingStep = nil
        surface.aquarium.stopFishing()
        surface.externallyPaused = true
        onClose?()
    }

    /// Fishing needs fish that are swimming.
    func refreshAvailability() {
        let config = store.configuration
        let reason: String?
        if config.mode != .live { reason = "The aquarium is a still image. Switch to Live to fish." }
        else if config.swimmingSpeed <= 0 { reason = "Swimming speed is zero, so nothing will bite. Raise it in Motion & light." }
        else if config.totalFish == 0 { reason = "There are no fish in the tank. Add some residents first." }
        else { reason = nil }
        if session.blocked != reason { session.blocked = reason }
        refreshAdvice()
    }

    /// A word of warning when the tackle cannot catch anything in this tank.
    func refreshAdvice() {
        let config = store.configuration, log = store.angling
        var advice: String?
        if log.hook == .circle && config.count(.koi) == 0 && config.count(.pearl) == 0 {
            advice = "No koi or gouramis here: small fish will only strip a circle hook."
        } else if log.hook == .circle && log.offering.isLure {
            advice = "A circle hook rarely catches on a lure. Try the fine hook."
        }
        if session.advice != advice { session.advice = advice }
    }

    /// Returns true when the key was the angler's.
    private func handleKey(_ event: NSEvent) -> Bool {
        // Keys belong to the angler only while the water has focus, so Space still presses a focused control.
        guard event.window === window, window.firstResponder === input || window.firstResponder === window else { return false }
        switch event.keyCode {
        case 49: // Space: strike, hold to reel.
            if event.type == .keyDown { if !event.isARepeat { press(at: nil) } } else { release() }
            return true
        case 53: // Escape: reel straight in.
            if event.type == .keyDown { reelIn() }
            return true
        default:
            return false
        }
    }

    func press(at point: CGPoint?) {
        let scene = surface.aquarium
        guard let rig = scene.rig else { return }
        if let blocked = session.blocked { session.say(blocked, priority: 3); return }
        switch rig.phase {
        case .stowed:
            if let point {
                let p = surface.convert(point, to: scene)
                if scene.isInWater(p) { scene.cast(toward: p) } else { session.say("Click below the surface to cast there.", priority: 1) }
            } else {
                scene.cast(x: 0.45, y: 0.5)
            }
        case .fighting:
            scene.setReeling(true)
        case .sinking, .fishing:
            // A bare hook: a click on the water reels in, rebaits, and casts there in one go.
            if !rig.offering.isLure && rig.baitLeft <= 0.04 && rig.holderID == nil {
                scene.reelIn()
                if let point { scene.cast(toward: surface.convert(point, to: scene)) } else { scene.cast(x: rig.castX, y: rig.setDepthY) }
                // Record the cast, but don't let "line in" talk over the fresh cast.
                for event in scene.drainFishingEvents() where event == .cast { store.angling.record(event) }
                session.card = nil
                session.say("Fresh \(store.angling.offering.title.lowercased()) on, and back in.", priority: 2, outcome: true)
                return
            }
            // A fish has the bait: strike at once, every millisecond counts.
            if rig.holderID != nil { scene.strike(); return }
            // Otherwise a quick click twitches the rig on release, and a press held a moment
            // becomes a steady retrieve without jerking the bait first.
            pressing = true
            heldToReel = false
            pressGeneration += 1
            let generation = pressGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                guard let self, self.pressing, self.pressGeneration == generation else { return }
                self.heldToReel = true
                self.surface.aquarium.setReeling(true)
            }
        case .landed:
            scene.reelIn()
        default:
            break
        }
    }

    func release() {
        if pressing && !heldToReel, let phase = surface.aquarium.rig?.phase, phase == .sinking || phase == .fishing {
            surface.aquarium.strike()
        }
        pressing = false
        heldToReel = false
        surface.aquarium.setReeling(false)
    }

    func reelIn() {
        guard let rig = surface.aquarium.rig else { return }
        if rig.phase == .fighting { session.say("A fish is on! Play it in first: hold to reel, let go when it runs.", priority: 2, outcome: true); return }
        surface.aquarium.reelIn()
    }

    // MARK: Readouts

    private func refresh() {
        let scene = surface.aquarium
        for event in scene.drainFishingEvents() { handle(event) }
        guard let r = scene.rig else { return }
        if session.phase != r.phase { session.phase = r.phase }
        let tension = r.phase == .fighting ? (r.pressure / r.hook.strength * 50).rounded() / 50 : 0
        if session.tension != tension { session.tension = tension }
        let slack = r.phase == .fighting && r.slackTime > 0.4
        if session.slack != slack { session.slack = slack }
        let bait = r.offering.isLure ? 1 : (r.baitLeft * 20).rounded() / 20
        if session.baitLeft != bait { session.baitLeft = bait }
        let line = r.phase == .fighting ? Int(r.lineLength * TankScale.waterHeightCM * TankScale.aspect) : 0
        if session.lineOutCM != line { session.lineOutCM = line }
        let strike = r.holderID != nil && !r.hook.setsItself
        if session.strikeNow != strike { session.strikeNow = strike }
        let running = r.phase == .fighting && r.running
        if session.running != running { session.running = running }
        // Only a koi runs with line; smaller fish dive against the rod.
        let diving = running && (r.hookedID.flatMap { id in scene.simulation.fish.first { $0.id == id } }.map { Tackle.fightStrength($0.species) < 0.6 } ?? false)
        if session.diving != diving { session.diving = diving }
        if session.card != nil, r.phase != .landed, Date().timeIntervalSince(session.cardShownAt) > 7 {
            session.card = nil
        }
    }

    static func spoken(_ species: FishSpecies) -> String { species == .crab ? "Thai micro crab" : species.name.lowercased() }
    static func article(_ offering: Offering) -> String {
        switch offering {
        case .bloodworm: return "a bloodworm"
        case .bread: return "a flake of bread"
        case .pellet: return "a soaked pellet"
        case .dryFly: return "a dry fly"
        case .spinner: return "a micro spinner"
        case .softWorm: return "a soft worm jig"
        }
    }

    /// Soft, optional cues from the system sound set, for the fishing window only.
    private func play(_ name: String, volume: Float) {
        guard store.angling.sounds ?? true, let sound = NSSound(named: name)?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }

    /// The moments a VoiceOver user must not miss.
    private func announce(_ text: String) {
        NSAccessibility.post(element: window, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private func handle(_ event: FishingEvent) {
        switch event {
        case .splash: play("Pop", volume: 0.25)
        case .take: if !store.angling.hook.setsItself { play("Tink", volume: 0.45) }
        case .hooked: play("Morse", volume: 0.3)
        case .landed: play("Glass", volume: 0.35)
        case .threwHook, .lineSnapped, .hookStraightened, .hookPulled: play("Blow", volume: 0.2)
        default: break
        }
        speak(event)
        switch event {
        case .take, .hooked, .landed, .threwHook, .lineSnapped, .hookStraightened, .hookPulled, .missed, .spat: announce(session.status)
        default: break
        }
    }

    private func speak(_ event: FishingEvent) {
        let log = store.angling
        let bait = store.angling.offering.title.lowercased()
        let circle = store.angling.hook.setsItself
        switch event {
        case .cast:
            store.angling.record(event)
            session.card = nil
            session.say("Casting…", priority: 0)
        case .splash: session.say("Plop.", priority: 0)
        case .spooked(let s): session.say("Plop! The splash scattered a \(Self.spoken(s)). Give them a moment.", priority: 1)
        case .curious(let s): session.say("That sounded like feeding time. A \(Self.spoken(s)) comes to look.", priority: 1)
        case .settled:
            let offering = store.angling.offering
            if offering.floats { session.say("The fly sits on the film. Click to twitch it; watch for a rise.", priority: 0) }
            else if offering.isLure { session.say("Your \(bait) is on the bottom. Hold to swim it in, click to make it dart.", priority: 0) }
            else { session.say("Your \(bait) hangs under the float. Watch the float…", priority: 0) }
        case .interest(let s): session.say("A \(Self.spoken(s)) has noticed your \(bait).", priority: 0)
        case .following(let s): session.say("A \(Self.spoken(s)) is following your \(bait)… keep it moving, or pause it.", priority: 1)
        case .refused(let s): session.say("The \(Self.spoken(s)) looked it over and turned away.", priority: 1)
        case .nibble(let s):
            switch store.angling.offering {
            case .dryFly: session.say("A \(Self.spoken(s)) is nosing the fly… wait for it to take.", priority: 1)
            case .spinner, .softWorm: session.say("A \(Self.spoken(s)) is bumping your \(bait)… keep it moving.", priority: 1)
            default: session.say("Nibble, nibble… a \(Self.spoken(s)) is picking at it. Wait for the float to go under.", priority: 1)
            }
        case .baitStolen(let s):
            store.angling.record(event)
            session.say("Bait thief! A \(Self.spoken(s)) stripped your hook bare. Click the water to rebait and cast.", priority: 2, outcome: true)
        case .take(let s):
            store.angling.record(event)
            if circle { session.say("A \(Self.spoken(s)) has taken it. Don't strike, let the circle hook set as it turns…", priority: 3, outcome: true) }
            else { session.say(store.angling.offering.isLure ? "Hit! STRIKE!" : "The float slides under. STRIKE!", priority: 3, outcome: true) }
        case .struckEarly: session.say("Too early! You pulled it away from them.", priority: 2, outcome: true)
        case .twitch: break
        case .missed(let s): session.say("Missed. The \(Self.spoken(s)) let go and bolted.", priority: 2, outcome: true)
        case .spat(let s): session.say("The \(Self.spoken(s)) felt something wrong and spat it out.", priority: 2, outcome: true)
        case .hooked(let s):
            store.angling.record(event)
            if Tackle.fightStrength(s) < 0.3 { session.say("Fish on! A little \(Self.spoken(s)). Hold to lift it out.", priority: 3, outcome: true) }
            else if Tackle.fightStrength(s) < 0.6 { session.say("Fish on! A \(Self.spoken(s)). Hold to reel, but ease off when it dives.", priority: 3, outcome: true) }
            else { session.say("Fish on! A \(Self.spoken(s)). Hold to reel while it rests, let go when it runs.", priority: 3, outcome: true) }
        case .run(let s): session.say("The \(Self.spoken(s)) is running. Let it take line!", priority: 2)
        case .surfaceThrash(let s): session.say("Not beaten yet: the \(Self.spoken(s)) crashes at the surface and dives!", priority: 2)
        case .threwHook(let s):
            store.angling.record(event)
            session.say("Slack line… the \(Self.spoken(s)) shook its head and threw the hook.", priority: 3, outcome: true)
        case .lineSnapped(let s):
            store.angling.record(event)
            session.say("Snap! The \(Self.spoken(s)) broke the line. Tying on a new hook…", priority: 3, outcome: true)
        case .hookPulled(let s):
            store.angling.record(event)
            session.say("Too hard! The hook tore out of the \(Self.spoken(s))'s lip. Ease off when it dives.", priority: 3, outcome: true)
        case .hookStraightened(let s):
            store.angling.record(event)
            session.say("The \(Self.spoken(s)) straightened your fine-wire hook. Tying on another…", priority: 3, outcome: true)
        case .landed(let record):
            let first = log.tally(record.species).count == 0
            let best = store.angling.record(event)
            session.card = CatchCard(record: record, personalBest: best, firstOfSpecies: first)
            session.cardShownAt = Date()
            session.say("Landed! A \(Self.spoken(record.species)) of \(String(format: "%.1f", record.lengthCM)) cm.", priority: 3, outcome: true)
        case .released(let s): session.say("Back it goes. The \(Self.spoken(s)) will be wary of hooks for a while.", priority: 2)
        case .crabClinging: session.say("A crab is clinging to your bait and riding up with it!", priority: 2)
        case .crabLetGo: session.say("…and it lets go, tumbling back to the sand.", priority: 2)
        case .reeledIn: session.say("Line in. Click the water to cast.", priority: 1)
        case .rigReady: session.say("Ready. Click the water to cast.", priority: 1)
        }
    }
}

// MARK: - Views

private let accent = Color(nsColor: NSColor(rgb: 0x8db9ff))

struct FishingOverlay: View {
    @ObservedObject var session: FishingSession

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 10) {
                Text(session.blocked ?? session.status)
                    .font(.system(size: 16, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                if let advice = session.advice, session.blocked == nil {
                    Label(advice, systemImage: "lightbulb").font(.system(size: 12)).foregroundStyle(.yellow.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if session.strikeNow {
                    Text("STRIKE NOW · click or Space").font(.system(size: 13, weight: .bold)).tracking(1.4)
                        .padding(.horizontal, 10).padding(.vertical, 5).background(Color(nsColor: NSColor(rgb: 0xf05a28)), in: Capsule())
                }
                if session.phase == .fighting {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("LINE TENSION").font(.system(size: 11, weight: .semibold)).tracking(1.2).opacity(0.8)
                            if session.running {
                                Text(session.diving ? "DIVE!" : "RUN!").font(.system(size: 11, weight: .heavy)).tracking(1.2)
                                    .padding(.horizontal, 7).padding(.vertical, 2).background(Color.orange, in: Capsule())
                            }
                            Spacer()
                            Text(session.slack ? "SLACK. REEL!" : "\(session.lineOutCM) cm out").font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(session.slack ? Color.orange : .white.opacity(0.8))
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.14))
                                Capsule().fill(tensionColor).frame(width: max(6, geometry.size.width * min(1, session.tension)))
                                Rectangle().fill(.white.opacity(0.5)).frame(width: 1.5).offset(x: geometry.size.width * 0.85)
                            }
                        }.frame(height: 11)
                        Text(session.tension > 0.85 ? "Too much! Let go." : (session.running ? (session.diving ? "It's diving. Ease off or the hook tears out." : "It's running. Let go and let it take line.") : (session.slack ? "Keep the line tight or it will throw the hook." : "It's resting. Hold to reel.")))
                            .font(.system(size: 12)).opacity(0.85)
                    }.frame(width: 320)
                } else if session.phase == .fishing || session.phase == .sinking, session.baitLeft < 1 {
                    HStack(spacing: 8) {
                        Text("BAIT").font(.system(size: 11, weight: .semibold)).tracking(1.2).opacity(0.8)
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.14))
                                Capsule().fill(session.baitLeft > 0.04 ? accent : .orange).frame(width: max(4, geometry.size.width * session.baitLeft))
                            }
                        }.frame(width: 140, height: 6)
                        Text(session.baitLeft > 0.04 ? "\(Int(session.baitLeft * 100))%" : "bare hook · click to rebait").font(.system(size: 11, design: .monospaced)).opacity(0.8)
                    }
                }
            }
            .padding(16).frame(maxWidth: 420, alignment: .leading)
            .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 13))
            .padding(18)
            if let card = session.card {
                HStack { Spacer(); catchCard(card) }.padding(18)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var tensionColor: Color {
        session.tension > 0.85 ? Color(nsColor: NSColor(rgb: 0xf05a28)) : (session.tension > 0.6 ? .orange : Color(nsColor: NSColor(rgb: 0x5ccf8a)))
    }

    private func catchCard(_ card: CatchCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.firstOfSpecies ? "NEW SPECIES" : (card.personalBest ? "PERSONAL BEST" : "LANDED"))
                .font(.system(size: 9, weight: .bold)).tracking(1.6).foregroundStyle(card.firstOfSpecies || card.personalBest ? .yellow : accent)
            Image(nsImage: Artwork.fishImage(card.record.species)).resizable().aspectRatio(contentMode: .fit).frame(width: 200, height: 120)
            Text(card.record.species.name).font(.system(size: 20, weight: .regular))
            Text(String(format: "%.1f cm · %@", card.record.lengthCM, Self.weight(card.record.weightGrams)))
                .font(.system(size: 13, weight: .medium, design: .rounded)).monospacedDigit()
            Text(Tackle.comparison(grams: card.record.weightGrams)).font(.system(size: 11)).opacity(0.75)
            Text("\(card.record.hook.shortTitle) · \(card.record.offering.title)").font(.system(size: 11)).opacity(0.7)
            if card.record.caughtBefore {
                Text("You've caught this one before. It's learning.").font(.system(size: 11)).foregroundStyle(.yellow.opacity(0.9))
            }
            Text("Released unharmed.").font(.system(size: 11)).opacity(0.6)
        }
        .padding(16).frame(width: 232, alignment: .leading)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 13))
        .transition(.opacity)
    }

    static func weight(_ grams: Double) -> String {
        grams >= 1000 ? String(format: "%.2f kg", grams / 1000) : (grams >= 10 ? String(format: "%.0f g", grams) : String(format: "%.1f g", grams))
    }
}

struct FishingToolbar: View {
    @ObservedObject var store: AquariumStore
    @ObservedObject var session: FishingSession
    var reelIn: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "figure.fishing").font(.system(size: 20)).foregroundStyle(.secondary)
            Text("Hook").font(.system(size: 11)).foregroundStyle(.secondary)
            Picker("Hook", selection: $store.angling.hook) {
                ForEach(HookKind.allCases) { hook in Text(hook.shortTitle).tag(hook) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 290)
                .help(store.angling.hook.detail)
            Text("Bait").font(.system(size: 11)).foregroundStyle(.secondary)
            Picker("Bait", selection: $store.angling.offering) {
                Section("Bait, under a float") {
                    ForEach(Offering.allCases.filter { !$0.isLure }) { offering in Label(offering.title, systemImage: offering.symbol).tag(offering) }
                }
                Section("Lures") {
                    ForEach(Offering.allCases.filter(\.isLure)) { offering in Label(offering.title, systemImage: offering.symbol).tag(offering) }
                }
            }.labelsHidden().frame(width: 170)
                .help(store.angling.offering.detail)
            Button { store.angling.sounds = !(store.angling.sounds ?? true) } label: {
                Image(systemName: store.angling.sounds ?? true ? "speaker.wave.2" : "speaker.slash")
            }.buttonStyle(.borderless).help("Soft sound cues while fishing").accessibilityLabel(store.angling.sounds ?? true ? "Turn fishing sounds off" : "Turn fishing sounds on")
            Button(action: reelIn) { Label("Reel in", systemImage: "arrow.uturn.backward") }
                .disabled(session.phase == .stowed || session.phase == .fighting)
                .help("Bring the line straight in (Esc)")
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("Landed \(store.angling.landed) · \(store.angling.speciesCaught) of 8 species")
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                Text("Click water: cast · Click: strike · Hold: reel · Esc: reel in")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
