import AppKit
import SwiftUI
import SpriteKit
import ImageIO
import UniformTypeIdentifiers

// Renders scripted fishing sessions with the production renderer and saves the moments that
// matter (bait hanging, a nibble, the float going under, the fight, a lure followed, a crab
// hanging on) plus a contact sheet and a short GIF: `zsh tools/fishing-capture.sh [folder]`.

@main struct FishingCapture {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/fishing-review")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        print("Fishing capture: creating SpriteKit view (needs a graphical session)…"); fflush(stdout)
        let size = CGRect(x: 0, y: 0, width: 1280, height: 720)
        var saved: [(String, CGImage)] = []
        var gifFrames: [CGImage] = []

        func image(_ surface: AquariumSurface) -> CGImage {
            surface.texture(from: surface.aquarium, crop: CGRect(origin: .zero, size: surface.aquarium.size))!.cgImage()
        }
        func write(_ image: CGImage, _ name: String) throws {
            let url = output.appendingPathComponent(name)
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }

        /// Plays a session frame by frame like a skilled angler, capturing on the named events.
        func play(_ name: String, config: AquariumConfiguration, hook: HookKind, offering: Offering, cast: (Double, Double),
                  seconds: Double, wants: [String], gif: Bool = false) throws {
            let window = NSWindow(contentRect: size, styleMask: [.titled], backing: .buffered, defer: false)
            let surface = AquariumSurface(frame: size, configuration: config)
            window.contentView = surface; window.orderFront(nil)
            surface.isPaused = true
            let scene = surface.aquarium
            scene.advanceForReview(seconds: 3)
            scene.startFishing(hook: hook, offering: offering)
            var remaining = Set(wants)
            var strikeAt: Double?
            var t = 0.0
            var casts = 0
            var fightFrames = 0
            func shoot(_ key: String) {
                guard remaining.contains(key) else { return }
                remaining.remove(key)
                saved.append(("\(name)-\(key)", image(surface)))
                print("  captured \(name)-\(key) at \(String(format: "%.1f", t))s")
            }
            while t < seconds && !remaining.isEmpty {
                t += 1.0 / 30
                guard let rig = scene.rig else { break }
                switch rig.phase {
                case .stowed:
                    casts += 1
                    let jitter = Double(casts % 3) * 0.04
                    _ = scene.cast(x: cast.0 + jitter, y: cast.1)
                case .sinking, .fishing:
                    if let at = strikeAt, t >= at { scene.strike(); strikeAt = nil }
                    if offering.isLure && offering != .dryFly { scene.setReeling(rig.soak > 1.2 && (t.truncatingRemainder(dividingBy: 2.4) < 1.7)) }
                    if !offering.isLure && (rig.baitLeft <= 0.04 || rig.soak > 40) { scene.reelIn() }
                case .fighting:
                    scene.setReeling(!rig.running && rig.pressure < rig.hook.strength * 0.8)
                    fightFrames += 1
                    if gif && fightFrames % 3 == 0 && gifFrames.count < 75 { gifFrames.append(image(surface)) }
                    if fightFrames == 40 { shoot("fight") }
                    if rig.running && fightFrames > 60 { shoot("run") }
                default: scene.setReeling(false)
                }
                scene.advanceForReview(seconds: 1.0 / 30)
                for event in scene.drainFishingEvents() {
                    switch event {
                    case .settled: if t > 2 { shoot("settled") }
                    case .nibble: shoot("nibble")
                    case .take:
                        if !hook.setsItself { strikeAt = t + 0.3 }
                        // Let the float slide under first.
                        scene.advanceForReview(seconds: 0.2); t += 0.2
                        shoot("take")
                    case .following: scene.advanceForReview(seconds: 0.8); t += 0.8; shoot("follow")
                    case .crabClinging: shoot("crab")
                    case .splash: shoot("splash")
                    case .landed(let record): print("  landed \(record.species.name) \(record.lengthCM) cm")
                    default: break
                    }
                }
                if !(scene.rig?.crumbs.isEmpty ?? true) && t > 8 { shoot("crumbs") }
            }
            if !remaining.isEmpty { print("  (not seen in \(Int(seconds)) s: \(remaining.sorted().joined(separator: ", ")))") }
            window.orderOut(nil)
        }

        var community = AquariumConfiguration()
        community.lighting = .day
        community.counts = Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map { ($0.rawValue, [FishSpecies.rasbora: 6, .cherry: 4, .golden: 4, .betta: 1, .koi: 1, .pearl: 2, .loach: 3, .shrimp: 4, .crab: 3, .danio: 4][$0] ?? 0) })
        try play("bloodworm", config: community, hook: .jHook, offering: .bloodworm, cast: (0.42, 0.5), seconds: 160,
                 wants: ["splash", "settled", "nibble", "take", "fight", "run"], gif: true)
        try play("bread", config: community, hook: .circle, offering: .bread, cast: (0.5, 0.55), seconds: 120, wants: ["crumbs", "take", "fight"])
        try play("spinner", config: community, hook: .jHook, offering: .spinner, cast: (0.3, 0.5), seconds: 120, wants: ["follow", "fight"])
        var bottom = community
        bottom.counts[FishSpecies.crab.rawValue] = 6
        try play("bottom", config: bottom, hook: .fine, offering: .bloodworm, cast: (0.35, 0.09), seconds: 200, wants: ["nibble", "crab"])
        var night = community
        night.lighting = .night
        try play("night", config: night, hook: .fine, offering: .dryFly, cast: (0.5, 0.8), seconds: 120, wants: ["settled", "take"])
        try play("nightfloat", config: night, hook: .fine, offering: .bloodworm, cast: (0.45, 0.5), seconds: 120, wants: ["settled", "take"])
        try play("fly", config: community, hook: .fine, offering: .dryFly, cast: (0.5, 0.8), seconds: 120, wants: ["take"])

        // The fishing window itself: production controller, overlay, and toolbar, composited over
        // the renderer's image (AppKit's bitmap cache leaves out the Metal layer).
        let store = AquariumStore(persist: false)
        store.configuration = community
        store.angling.offering = .bread
        store.angling.hook = .jHook
        let controller = FishingController(store: store)
        controller.show()
        controller.surface.isPaused = true
        let scene = controller.surface.aquarium
        scene.advanceForReview(seconds: 3)
        func windowShot(_ key: String) {
            guard let content = controller.window.contentView else { return }
            // Let SwiftUI apply the session's latest readouts before taking the picture.
            RunLoop.current.run(until: Date().addingTimeInterval(0.08))
            content.layoutSubtreeIfNeeded()
            let bounds = content.bounds
            let scale = controller.window.backingScaleFactor
            let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.scaleBy(x: scale, y: scale)
            let water = controller.surface.frame
            context.draw(image(controller.surface), in: water)
            for view in content.subviews where view is NSHostingView<FishingOverlay> || view is NSHostingView<FishingToolbar> {
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let cg = bitmap.cgImage { context.draw(cg, in: view.frame) }
            }
            if let shot = context.makeImage() { saved.append(("window-\(key)", shot)); print("  captured window-\(key): \(controller.session.status)") }
        }
        var wanted = ["ready", "nibble", "strike", "fight", "landed"]
        windowShot("ready"); wanted.removeFirst()
        var t = 0.0, strikeAt: Double?
        while t < 240 && !wanted.isEmpty {
            t += 1.0 / 30
            guard let rig = scene.rig else { break }
            if rig.phase == .stowed { scene.cast(x: 0.5, y: 0.55) }
            if rig.phase == .fighting { scene.setReeling(!rig.running && rig.pressure < rig.hook.strength * 0.8) } else { scene.setReeling(false) }
            if let at = strikeAt, t >= at { scene.strike(); strikeAt = nil }
            if (rig.phase == .fishing) && (rig.baitLeft <= 0.04 || rig.soak > 40) { scene.reelIn() }
            scene.advanceForReview(seconds: 1.0 / 30)
            let pending = scene.rig?.events ?? []
            scene.afterFishingStep?()
            for event in pending {
                switch event {
                case .nibble where wanted.first == "nibble": scene.advanceForReview(seconds: 0.1); windowShot("nibble"); wanted.removeFirst()
                case .take:
                    strikeAt = t + 0.35
                    if wanted.first == "strike" { scene.advanceForReview(seconds: 0.15); scene.afterFishingStep?(); windowShot("strike"); wanted.removeFirst() }
                default: break
                }
            }
            if wanted.first == "fight", scene.rig?.phase == .fighting, (scene.rig?.fightTime ?? 0) > 1.5 { windowShot("fight"); wanted.removeFirst() }
            if wanted.first == "landed", scene.rig?.phase == .landed { windowShot("landed"); wanted.removeFirst() }
            if wanted.first == "nibble" && t > 120 { wanted.removeFirst() }
            if wanted.first == "strike" && t > 160 { wanted.removeFirst() }
        }
        controller.window.close()

        for (name, image) in saved { try write(image, "\(name).png") }
        // Contact sheet: every capture in a grid of half-size frames.
        let columns = 3, w = 640, h = 360
        let rows = (saved.count + columns - 1) / columns
        if rows > 0, let sheet = CGContext(data: nil, width: columns * w, height: rows * h, bitsPerComponent: 8, bytesPerRow: columns * w * 4,
                                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            sheet.setFillColor(CGColor(gray: 0.1, alpha: 1)); sheet.fill(CGRect(x: 0, y: 0, width: columns * w, height: rows * h))
            for (i, item) in saved.enumerated() {
                let x = (i % columns) * w, y = (rows - 1 - i / columns) * h
                sheet.draw(item.1, in: CGRect(x: x, y: y, width: w, height: h))
                let label = NSAttributedString(string: item.0, attributes: [.font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: NSColor.white])
                let line = CTLineCreateWithAttributedString(label)
                sheet.textPosition = CGPoint(x: x + 12, y: y + h - 28)
                CTLineDraw(line, sheet)
            }
            if let image = sheet.makeImage() { try write(image, "contact-sheet.png") }
        }
        if !gifFrames.isEmpty {
            let url = output.appendingPathComponent("fight.gif")
            if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, gifFrames.count, nil) {
                CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
                for frame in gifFrames {
                    CGImageDestinationAddImage(destination, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
                }
                CGImageDestinationFinalize(destination)
            }
        }
        print("Saved \(saved.count) fishing captures to \(output.path)")
    }
}
