import AppKit
import SpriteKit

/// Terminal tackle drawn once into small textures: hooks with a dark outline and a bright wire
/// highlight so they read against water, a float, and each bait and lure.
enum FishingArt {
    private static func texture(width: Int, height: Int, _ draw: (CGContext) -> Void) -> SKTexture {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setLineCap(.round)
        context.setLineJoin(.round)
        draw(context)
        let texture = SKTexture(cgImage: context.makeImage()!)
        texture.filteringMode = .linear
        return texture
    }

    private static func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    /// A hook hangs eye-up in a 64×128 canvas: eye at the top, bend at the bottom, the bait
    /// threaded on around the bend. The anchor (eye) is at (0.5, 0.92).
    nonisolated(unsafe) static let hooks: [HookKind: SKTexture] = Dictionary(uniqueKeysWithValues: HookKind.allCases.map { kind in
        (kind, texture(width: 64, height: 128) { c in
            let path = CGMutablePath()
            let eye = CGPoint(x: 32, y: 116)
            switch kind {
            case .fine, .jHook:
                let gap: CGFloat = kind == .fine ? 11 : 15
                path.move(to: CGPoint(x: 32, y: 110))
                path.addLine(to: CGPoint(x: 32, y: 38))
                path.addArc(center: CGPoint(x: 32 - gap, y: 38), radius: gap, startAngle: 0, endAngle: .pi, clockwise: true)
                path.addLine(to: CGPoint(x: 32 - 2 * gap, y: 58))
                // The barb.
                path.move(to: CGPoint(x: 32 - 2 * gap, y: 56))
                path.addLine(to: CGPoint(x: 32 - 2 * gap + 5, y: 50))
            case .circle:
                path.move(to: CGPoint(x: 32, y: 110))
                path.addLine(to: CGPoint(x: 32, y: 52))
                path.addArc(center: CGPoint(x: 18, y: 52), radius: 14, startAngle: 0, endAngle: .pi * 1.62, clockwise: true)
                // The point turns back in toward the shank.
                path.addLine(to: CGPoint(x: 26, y: 70))
            }
            let wire: CGFloat = kind == .fine ? 2.6 : (kind == .jHook ? 3.4 : 4.2)
            let metal: CGColor
            switch kind {
            case .fine: metal = color(0.72, 0.55, 0.32)
            case .jHook: metal = color(0.80, 0.82, 0.85)
            case .circle: metal = color(0.22, 0.23, 0.26)
            }
            c.addPath(path); c.setStrokeColor(color(0.05, 0.07, 0.09, 0.55)); c.setLineWidth(wire + 2.4); c.strokePath()
            c.addPath(path); c.setStrokeColor(metal); c.setLineWidth(wire); c.strokePath()
            c.translateBy(x: 0.8, y: 0.8)
            c.addPath(path); c.setStrokeColor(color(1, 1, 1, kind == .circle ? 0.35 : 0.7)); c.setLineWidth(max(0.8, wire * 0.3)); c.strokePath()
            c.translateBy(x: -0.8, y: -0.8)
            c.setStrokeColor(metal); c.setLineWidth(wire * 0.8)
            c.strokeEllipse(in: CGRect(x: eye.x - 4.5, y: eye.y - 6, width: 9, height: 11))
        })
    })

    /// A slim waggler: orange tip, white body, a dark stem. 32×128, the waterline at 0.62.
    nonisolated(unsafe) static let float: SKTexture = texture(width: 32, height: 128) { c in
        c.setFillColor(color(0.10, 0.10, 0.11)); c.fill(CGRect(x: 15, y: 4, width: 2, height: 36))
        let body = CGPath(ellipseIn: CGRect(x: 8, y: 30, width: 16, height: 58), transform: nil)
        c.addPath(body); c.setFillColor(color(0.93, 0.91, 0.86)); c.fillPath()
        c.addPath(body); c.setStrokeColor(color(0.2, 0.2, 0.22, 0.6)); c.setLineWidth(1.2); c.strokePath()
        c.setFillColor(color(1, 1, 1, 0.55)); c.fillEllipse(in: CGRect(x: 11, y: 44, width: 4, height: 30))
        c.setFillColor(color(0.97, 0.36, 0.08)); c.fill(CGRect(x: 13, y: 84, width: 6, height: 38))
        c.setFillColor(color(1, 0.75, 0.4, 0.8)); c.fill(CGRect(x: 14, y: 86, width: 1.6, height: 34))
    }

    /// Baits and lures, each centred on the hook's bend in a 64×64 canvas.
    nonisolated(unsafe) static let offerings: [Offering: SKTexture] = Dictionary(uniqueKeysWithValues: Offering.allCases.map { offering in
        (offering, texture(width: 64, height: 64) { c in
            switch offering {
            case .bloodworm:
                // A red midge larva threaded on, both ends hanging in loose curls.
                let worm = CGMutablePath()
                worm.move(to: CGPoint(x: 10, y: 44))
                worm.addCurve(to: CGPoint(x: 32, y: 30), control1: CGPoint(x: 6, y: 26), control2: CGPoint(x: 24, y: 22))
                worm.addCurve(to: CGPoint(x: 52, y: 14), control1: CGPoint(x: 40, y: 38), control2: CGPoint(x: 58, y: 30))
                c.addPath(worm); c.setStrokeColor(color(0.35, 0.02, 0.03)); c.setLineWidth(7.5); c.strokePath()
                c.addPath(worm); c.setStrokeColor(color(0.78, 0.07, 0.08)); c.setLineWidth(5.5); c.strokePath()
                c.setLineDash(phase: 0, lengths: [1.2, 3])
                c.addPath(worm); c.setStrokeColor(color(0.4, 0.02, 0.03, 0.8)); c.setLineWidth(5.5); c.strokePath()
                c.setLineDash(phase: 0, lengths: [])
                c.addPath(worm); c.setStrokeColor(color(1, 0.55, 0.5, 0.55)); c.setLineWidth(1.4); c.strokePath()
            case .bread:
                // A pinched flake of white bread, soft and torn at the edges.
                let puffs: [(CGFloat, CGFloat, CGFloat)] = [(32, 32, 15), (21, 37, 10), (43, 36, 11), (26, 22, 10), (40, 23, 9), (33, 44, 9)]
                for (x, y, r) in puffs { c.setFillColor(color(0.84, 0.80, 0.68, 0.55)); c.fillEllipse(in: CGRect(x: x - r - 1.5, y: y - r - 1.5, width: 2 * r + 3, height: 2 * r + 3)) }
                for (x, y, r) in puffs { c.setFillColor(color(0.97, 0.95, 0.88, 0.92)); c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) }
                c.setFillColor(color(0.86, 0.8, 0.66, 0.5)); c.fillEllipse(in: CGRect(x: 24, y: 24, width: 10, height: 8))
            case .pellet:
                let ball = CGRect(x: 19, y: 19, width: 26, height: 26)
                let colors = [color(0.72, 0.48, 0.25), color(0.42, 0.24, 0.12)] as CFArray
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
                c.saveGState(); c.addEllipse(in: ball); c.clip()
                c.drawRadialGradient(gradient, startCenter: CGPoint(x: 27, y: 37), startRadius: 1, endCenter: CGPoint(x: 32, y: 32), endRadius: 15, options: [])
                c.restoreGState()
                c.setFillColor(color(1, 0.95, 0.85, 0.6)); c.fillEllipse(in: CGRect(x: 24, y: 36, width: 5, height: 4))
            case .dryFly:
                // Seen from below: a ring of hackle fibres, a slim body, and the tail whisks.
                c.setStrokeColor(color(0.36, 0.25, 0.16, 0.85)); c.setLineWidth(1.1)
                for i in 0..<18 {
                    let a = Double(i) / 18 * 2 * .pi
                    c.move(to: CGPoint(x: 36, y: 38)); c.addLine(to: CGPoint(x: 36 + cos(a) * 15, y: 38 + sin(a) * 9))
                }
                c.strokePath()
                c.setFillColor(color(0.55, 0.45, 0.32)); c.fillEllipse(in: CGRect(x: 12, y: 34, width: 26, height: 7))
                c.setStrokeColor(color(0.6, 0.55, 0.45, 0.9)); c.setLineWidth(1)
                c.move(to: CGPoint(x: 13, y: 37)); c.addLine(to: CGPoint(x: 2, y: 42)); c.move(to: CGPoint(x: 13, y: 37)); c.addLine(to: CGPoint(x: 3, y: 33)); c.strokePath()
                c.setFillColor(color(0.75, 0.78, 0.82, 0.55)); c.fillEllipse(in: CGRect(x: 30, y: 40, width: 9, height: 16))
            case .spinner:
                // Body and bead; the blade is a separate texture so it can turn.
                c.setStrokeColor(color(0.75, 0.76, 0.78)); c.setLineWidth(1.6)
                c.move(to: CGPoint(x: 32, y: 62)); c.addLine(to: CGPoint(x: 32, y: 14)); c.strokePath()
                c.setFillColor(color(0.85, 0.12, 0.1)); c.fillEllipse(in: CGRect(x: 28.5, y: 40, width: 7, height: 7))
                c.setFillColor(color(0.70, 0.62, 0.30)); c.fill(CGRect(x: 29, y: 18, width: 6, height: 20))
                c.setFillColor(color(1, 0.95, 0.7, 0.6)); c.fill(CGRect(x: 30, y: 19, width: 1.5, height: 18))
            case .softWorm:
                // A painted lead jig head and a pink worm with a curly tail.
                let worm = CGMutablePath()
                worm.move(to: CGPoint(x: 40, y: 38))
                worm.addCurve(to: CGPoint(x: 12, y: 26), control1: CGPoint(x: 30, y: 30), control2: CGPoint(x: 22, y: 34))
                worm.addCurve(to: CGPoint(x: 10, y: 12), control1: CGPoint(x: 2, y: 20), control2: CGPoint(x: 16, y: 14))
                c.addPath(worm); c.setStrokeColor(color(0.62, 0.22, 0.38)); c.setLineWidth(7); c.strokePath()
                c.addPath(worm); c.setStrokeColor(color(0.95, 0.45, 0.62)); c.setLineWidth(5); c.strokePath()
                c.setFillColor(color(0.78, 0.86, 0.12)); c.fillEllipse(in: CGRect(x: 36, y: 33, width: 14, height: 13))
                c.setFillColor(color(0.08, 0.08, 0.08)); c.fillEllipse(in: CGRect(x: 43, y: 39, width: 4, height: 4))
                c.setFillColor(color(1, 1, 1, 0.8)); c.fillEllipse(in: CGRect(x: 44, y: 41, width: 1.5, height: 1.5))
            }
        })
    })

    /// A small air bubble seen from below: a silvery body with a dark rim where the light bends
    /// away, and a bright spot on top.
    nonisolated(unsafe) static let airBubble: SKTexture = texture(width: 32, height: 32) { c in
        c.setFillColor(color(0.85, 0.93, 1, 0.35)); c.fillEllipse(in: CGRect(x: 4, y: 4, width: 24, height: 24))
        c.setStrokeColor(color(0.12, 0.22, 0.3, 0.75)); c.setLineWidth(2.6); c.strokeEllipse(in: CGRect(x: 4, y: 4, width: 24, height: 24))
        c.setStrokeColor(color(1, 1, 1, 0.85)); c.setLineWidth(1.6)
        c.addArc(center: CGPoint(x: 16, y: 16), radius: 9, startAngle: .pi * 0.55, endAngle: .pi * 0.95, clockwise: false); c.strokePath()
        c.setFillColor(color(1, 1, 1, 0.95)); c.fillEllipse(in: CGRect(x: 18, y: 18, width: 5, height: 5))
    }

    /// Ripples on the film seen from below, drawn by hand rather than as perfect ellipses: a broken,
    /// wavering crest that thickens and thins, a dark trough just outside it, and the far side
    /// fainter than the near. Three variants so neighbouring rings never match. 256×80, the ring
    /// spanning 224×56.
    nonisolated(unsafe) static let ripples: [SKTexture] = (0..<3).map { variant in
        texture(width: 256, height: 80) { c in
            let phase = Double(variant) * 1.9 + 0.4
            let steps = 220
            func point(_ a: Double, _ grow: Double) -> CGPoint {
                let wobble = 1 + 0.045 * sin(3 * a + phase) + 0.025 * sin(5 * a + phase * 2.3)
                return CGPoint(x: 128 + cos(a) * 112 * wobble * grow, y: 40 + sin(a) * 28 * wobble * grow)
            }
            c.setLineCap(.butt)
            // Passes: a soft wide glow, the dark trough outside the crest, then the crest itself.
            let passes: [(grow: Double, width: Double, color: (Double, Double, Double), alpha: Double)] = [
                (1.0, 13, (1, 1, 1), 0.14), (1.075, 7.5, (0.08, 0.17, 0.25), 0.66), (1.0, 4.8, (1, 1, 1), 1)]
            for pass in passes {
                for i in 0..<steps {
                    let a0 = Double(i) / Double(steps) * 2 * .pi, a1 = Double(i + 1) / Double(steps) * 2 * .pi
                    let mask = 0.5 + 0.5 * sin(4 * a0 + phase * 1.7) * cos(a0 + phase)
                    let gap = ((mask - 0.2) / 0.2).clamped(to: 0...1)
                    let near = sin(a0) > 0 ? 1.0 : 0.5
                    let taper = 0.5 + 0.5 * (0.5 + 0.5 * sin(2 * a0 + phase))
                    let alpha = pass.alpha * gap * near
                    guard alpha > 0.01 else { continue }
                    c.move(to: point(a0, pass.grow)); c.addLine(to: point(a1, pass.grow))
                    c.setStrokeColor(color(pass.color.0, pass.color.1, pass.color.2, alpha))
                    c.setLineWidth(pass.width * taper)
                    c.strokePath()
                }
            }
        }
    }

    /// The bright collar of film around a float's tip or under a fly's feet: from below, where
    /// something pokes through the surface the film bends the light into a small silver ring.
    nonisolated(unsafe) static let meniscus: SKTexture = texture(width: 64, height: 24) { c in
        c.setFillColor(color(1, 1, 1, 0.18)); c.fillEllipse(in: CGRect(x: 4, y: 4, width: 56, height: 16))
        c.setStrokeColor(color(1, 1, 1, 0.9)); c.setLineWidth(2.4); c.strokeEllipse(in: CGRect(x: 8, y: 6, width: 48, height: 12))
        c.setStrokeColor(color(0.1, 0.2, 0.28, 0.35)); c.setLineWidth(1.4); c.strokeEllipse(in: CGRect(x: 5, y: 3.5, width: 54, height: 17))
    }

    nonisolated(unsafe) static let spinnerBlade: SKTexture = texture(width: 32, height: 48) { c in
        let blade = CGPath(ellipseIn: CGRect(x: 4, y: 3, width: 24, height: 42), transform: nil)
        let colors = [color(0.98, 0.98, 1), color(0.62, 0.66, 0.72), color(0.9, 0.85, 0.6)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.6, 1])!
        c.saveGState(); c.addPath(blade); c.clip()
        c.drawLinearGradient(gradient, start: CGPoint(x: 6, y: 44), end: CGPoint(x: 28, y: 2), options: [])
        c.restoreGState()
        c.addPath(blade); c.setStrokeColor(color(0.3, 0.32, 0.36, 0.7)); c.setLineWidth(1.2); c.strokePath()
    }
}

/// Everything of the angler's in the water: line, float, hook, bait or lure, the splash where it
/// went in, and crumbs drifting off a soft bait. Rebuilt in place every frame from the rig.
final class FishingLayer: SKNode {
    private let line = SKShapeNode()
    private let airLine = SKShapeNode()
    private let floatNode = SKSpriteNode(texture: FishingArt.float)
    private let hookNode = SKSpriteNode()
    private let baitNode = SKSpriteNode()
    private let bladeNode = SKSpriteNode(texture: FishingArt.spinnerBlade)
    private var rings: [SKSpriteNode] = []
    private var splashBubbles: [SKSpriteNode] = []
    private var crumbNodes: [SKSpriteNode] = []
    private let tipGlow = SKSpriteNode(texture: Artwork.softDot)
    private var takeRings: [SKSpriteNode] = []
    private var takeBubbles: [SKSpriteNode] = []
    private let collar = SKSpriteNode(texture: FishingArt.meniscus)
    private let dent = SKSpriteNode(texture: Artwork.softDot)
    private let flash = SKSpriteNode(texture: Artwork.softDot)
    private var shotNodes: [SKSpriteNode] = []

    override init() {
        super.init()
        for node in [line, airLine] {
            node.lineCap = .round
            node.isAntialiased = true
            addChild(node)
        }
        line.lineWidth = 1.1
        airLine.lineWidth = 0.9
        for node in [floatNode, hookNode, baitNode, bladeNode] { addChild(node) }
        tipGlow.colorBlendFactor = 1
        tipGlow.color = NSColor(srgbRed: 1, green: 0.62, blue: 0.2, alpha: 1)
        tipGlow.blendMode = .add
        addChild(tipGlow)
        for i in 0..<2 {
            let ring = SKSpriteNode(texture: FishingArt.ripples[(i + 1) % 3])
            ring.isHidden = true
            addChild(ring); takeRings.append(ring)
        }
        dent.colorBlendFactor = 1
        dent.color = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.28, alpha: 1)
        flash.colorBlendFactor = 1
        flash.color = NSColor(srgbRed: 0.9, green: 0.95, blue: 1, alpha: 1)
        flash.blendMode = .add
        for node in [collar, dent, flash] { node.isHidden = true; addChild(node) }
        for _ in 0..<3 {
            let bubble = SKSpriteNode(texture: FishingArt.airBubble)
            bubble.isHidden = true
            addChild(bubble); takeBubbles.append(bubble)
        }
        for _ in 0..<2 {
            let shot = SKSpriteNode(texture: Artwork.mote)
            shot.colorBlendFactor = 1
            addChild(shot); shotNodes.append(shot)
        }
        for i in 0..<3 {
            let ring = SKSpriteNode(texture: FishingArt.ripples[i])
            ring.isHidden = true
            addChild(ring); rings.append(ring)
        }
        for _ in 0..<10 {
            let bubble = SKSpriteNode(texture: Artwork.softDot)
            bubble.colorBlendFactor = 1
            bubble.color = .white
            bubble.isHidden = true
            addChild(bubble); splashBubbles.append(bubble)
        }
        for _ in 0..<16 {
            let crumb = SKSpriteNode(texture: Artwork.softDot)
            crumb.colorBlendFactor = 1
            crumb.isHidden = true
            addChild(crumb); crumbNodes.append(crumb)
        }
    }
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Places a ripple on the film. Ripples are drawn into textures, so they broaden as they spread.
    private func styleRing(_ ring: SKSpriteNode, radius: Double, flat: Double = 0.18, at position: CGPoint, alpha: Double, night: Double, z: CGFloat) {
        ring.size = CGSize(width: radius * 2 * 256 / 224, height: radius * 2 * flat * 80 / 56)
        ring.position = position
        // At night the rings must never outshine the float's glowing tip.
        ring.alpha = CGFloat(min(alpha, 1 - night * 0.65))
        ring.color = NSColor(srgbRed: 0.55, green: 0.65, blue: 0.85, alpha: 1)
        ring.colorBlendFactor = CGFloat(night * 0.6)
        ring.zPosition = z
        ring.isHidden = false
    }

    /// How upright the float stands, from its angle (1 upright, 0 lying flat).
    private func cock(of angle: Double) -> Double { 1 - min(1, abs(angle) / (.pi / 2)) }

    /// `scale`: points per 900-point-scene point. `night` 0...1 dims and blues the tackle.
    func update(rig r: FishingRig, framing: AquariumFraming, scale: Double, night: Double) {
        let point = { (x: Double, y: Double) in framing.point(x: x, y: y) }
        let layer = CGFloat(ParticlePerspective.layer(r.depth))
        let dim = 1 - night * 0.55
        func tint(_ c: NSColor) -> NSColor {
            let s = c.usingColorSpace(.sRGB) ?? c
            return NSColor(srgbRed: s.redComponent * dim, green: s.greenComponent * dim, blue: min(1, s.blueComponent * dim * (1 + night * 0.25)), alpha: s.alphaComponent)
        }
        let visible = r.phase != .stowed && r.phase != .retying
        isHidden = !visible
        guard visible else { return }
        let surface = point(r.x, r.surfaceY).y
        let tip = point(r.rodTipX, r.rodTipY)
        let rig = point(r.x, r.y)
        let hookLength = r.hook.drawnLength * scale
        let inMouth = r.phase == .fighting || r.holderID != nil || r.phase == .landed

        // The float rides the film, slides under with a taking fish, and bobs with each peck.
        let showFloat = r.offering.usesFloat && r.phase != .flying && r.phase != .landed
        floatNode.isHidden = !showFloat
        let floatHeight = 52 * scale
        var floatBase = point(r.floatX, r.surfaceY)
        if showFloat {
            let ripple = sin(r.bobClock * 1.7) * 0.6 * scale
            let bob = -r.floatBob * 5 * scale * abs(sin(r.bobClock * 14))
            // A fish with the bait drags the float right under and away at a slant.
            let pulled = r.holderID != nil || r.phase == .fighting
            // (A lifted float doesn't climb out: it keels over and lies in the film.)
            floatBase.y += CGFloat(ripple + bob - max(0, r.floatDip) * floatHeight * (pulled ? 0.95 : 0.75))
            if pulled && r.phase != .fighting {
                // A strong take keeps drawing it down along the line toward the bait.
                let draw = CGFloat(max(0, r.floatDip - 0.5) * 0.3)
                floatBase.x += (rig.x - floatBase.x) * draw
                floatBase.y += (rig.y - floatBase.y) * draw
            }
            floatNode.size = CGSize(width: floatHeight * 0.25, height: floatHeight)
            // A float lies flat until the sinking shot cocks it upright; a fish taking the bait on
            // the drop leaves it lying there, the sign anglers watch for.
            var cock = 1.0
            if r.phase == .sinking {
                let fallen = ((r.surfaceY - r.y) / max(0.01, r.surfaceY - r.setDepthY)).clamped(to: 0...1)
                let t = ((fallen - 0.55) / 0.45).clamped(to: 0...1)
                cock = t * t * (3 - 2 * t)
            }
            // A lift bite: the shot comes off the bottom and the float keels over to lie flat.
            cock = min(cock, 1 - (-r.floatDip / 0.3).clamped(to: 0...1))
            // The line from the bait drags the foot toward it; a sail-away stays more upright.
            // A sail-away stays more upright as it runs; a small fish pulls it straight down.
            let pull = pulled ? (r.holderID == nil ? 0.9 : (r.biteStyle == .sailAway ? 0.45 : (r.biteStyle == .dips ? 0.2 : 0.9))) : 0.5
            let lean = max(0, r.floatDip) * pull * (r.x < r.floatX ? -1 : 1) + sin(r.bobClock * 1.3) * 0.04
            let angle = lean * cock - .pi / 2 * (1 - cock)
            // The waterline sits at 62% of the float's height, so a cocked float shows its tip.
            let waterline = floatHeight * 0.12 * cock
            floatNode.position = CGPoint(x: floatBase.x + CGFloat(waterline * sin(angle)), y: floatBase.y - CGFloat(waterline * cos(angle)))
            floatNode.zRotation = CGFloat(angle)
            floatNode.zPosition = layer + 0.01
            // Under the film it loses its colour to the water, but not while it is the thing to
            // watch: the orange tip stays bright until the fish lets go.
            let drowned = r.holderID == nil ? max(0, r.floatDip - 0.3) / 0.7 : 0
            floatNode.color = tint(NSColor(srgbRed: 0.58, green: 0.74, blue: 0.86, alpha: 1))
            floatNode.colorBlendFactor = CGFloat(min(0.8, night * 0.6 + drowned * 0.45))
            floatNode.alpha = CGFloat(1 - drowned * 0.25)
        }
        let floatAngle = Double(floatNode.zRotation)
        let floatFoot = CGPoint(x: floatNode.position.x + CGFloat(sin(floatAngle) * floatHeight * 0.5),
                                y: floatNode.position.y - CGFloat(cos(floatAngle) * floatHeight * 0.5))
        let floatTop = CGPoint(x: floatNode.position.x - CGFloat(sin(floatAngle) * floatHeight * 0.5),
                               y: floatNode.position.y + CGFloat(cos(floatAngle) * floatHeight * 0.5))
        // Where the float's tip or the fly's feet break the film, a small silver collar. It snaps
        // shut the instant the tip goes under: the moment anglers strike on.
        let fishingFilm = (r.phase == .fishing || r.phase == .sinking)
        if showFloat && fishingFilm {
            let lying = 1 - cock(of: Double(floatNode.zRotation))
            let width = floatHeight * (0.36 + 0.6 * lying)
            collar.size = CGSize(width: width, height: width * 0.3)
            collar.position = CGPoint(x: floatBase.x, y: surface)
            collar.alpha = CGFloat(0.85 * (1 - 0.55 * lying) * (1 - (max(0, r.floatDip) / 0.2).clamped(to: 0...1)) * (1 - night * 0.5))
            collar.isHidden = collar.alpha < 0.02
        } else if r.offering.floats && fishingFilm && r.holderID == nil {
            collar.size = CGSize(width: 18 * scale, height: 5.5 * scale)
            collar.position = CGPoint(x: rig.x, y: surface)
            collar.alpha = CGFloat(0.75 * (1 - night * 0.5))
            collar.isHidden = false
        } else {
            collar.isHidden = true
        }
        collar.zPosition = layer + 0.012
        // A glow-stick tip at night.
        // A dry fly at night catches a glint of moonlight on the film.
        let flyGlint = r.offering.floats && r.inWater && r.holderID == nil
        tipGlow.isHidden = !(showFloat || flyGlint) || night < 0.15
        tipGlow.position = showFloat ? CGPoint(x: floatTop.x + (floatFoot.x - floatTop.x) * 0.12, y: floatTop.y + (floatFoot.y - floatTop.y) * 0.12) : rig
        tipGlow.size = CGSize(width: (showFloat ? 22 : 16) * scale, height: (showFloat ? 22 : 10) * scale)
        tipGlow.color = showFloat ? NSColor(srgbRed: 1, green: 0.62, blue: 0.2, alpha: 1) : NSColor(srgbRed: 0.75, green: 0.85, blue: 1, alpha: 1)
        tipGlow.alpha = CGFloat(min(1, night * 1.1) * (showFloat ? 1 - r.floatDip * 0.6 : 0.55))
        tipGlow.zPosition = layer + 0.02
        // The hook hangs from its eye; the bait sits on the bend.
        let eye = inMouth ? rig : CGPoint(x: rig.x, y: rig.y + CGFloat(hookLength * 0.42))
        hookNode.isHidden = inMouth || r.phase == .flying
        hookNode.texture = FishingArt.hooks[r.hook]
        hookNode.size = CGSize(width: hookLength * 0.5, height: hookLength)
        hookNode.anchorPoint = CGPoint(x: 0.5, y: 0.92)
        hookNode.position = eye
        // A lure being pulled leans toward the angler; a hanging bait hangs straight.
        let lean = !r.offering.usesFloat && r.speed > 0.005 ? -0.9 : sin(r.bobClock * 0.9) * 0.05
        hookNode.zRotation = CGFloat(lean)
        hookNode.zPosition = layer
        hookNode.color = tint(.white); hookNode.colorBlendFactor = CGFloat(night * 0.6)

        let lureOnLip = inMouth && r.offering.isLure && r.phase == .fighting
        let showBait = (!inMouth || lureOnLip) && (r.offering.isLure || r.baitLeft > 0.04) && r.phase != .landed
        baitNode.isHidden = !showBait
        if showBait {
            let size = hookLength * (r.offering.isLure ? 1.25 : 1.0) * (r.offering.isLure ? 1 : 0.45 + 0.55 * r.baitLeft)
            baitNode.texture = FishingArt.offerings[r.offering]
            baitNode.size = CGSize(width: size, height: size)
            let bend = CGPoint(x: eye.x + CGFloat(sin(lean) * hookLength * 0.8), y: eye.y - CGFloat(cos(lean) * hookLength * 0.8))
            baitNode.position = lureOnLip ? CGPoint(x: rig.x, y: rig.y - CGFloat(size * 0.25)) : bend
            baitNode.zRotation = CGFloat(lean + (r.offering == .bloodworm ? sin(r.bobClock * 2.3) * 0.12 : 0))
            baitNode.zPosition = layer + 0.002
            baitNode.color = tint(.white); baitNode.colorBlendFactor = CGFloat(night * 0.6)
            baitNode.alpha = r.phase == .flying ? 0.55 : 1
        }
        // A spinner's blade turns while it moves, flashing as it catches the light.
        let spinning = r.offering == .spinner && showBait
        bladeNode.isHidden = !spinning
        if spinning {
            let size = hookLength * 0.62
            let turn = r.bobClock * (6 + r.speed * 900)
            let face = r.speed > 0.004 ? abs(cos(turn)) : 0.85
            bladeNode.size = CGSize(width: size * 0.66 * max(0.12, face), height: size)
            bladeNode.position = CGPoint(x: baitNode.position.x - CGFloat(size * 0.35), y: baitNode.position.y + CGFloat(size * 0.45))
            bladeNode.zRotation = baitNode.zRotation + 0.5
            bladeNode.zPosition = layer + 0.003
            bladeNode.colorBlendFactor = CGFloat(0.4 * (1 - face) + night * 0.5)
            bladeNode.color = tint(NSColor(white: 0.5, alpha: 1))
        }

        // Line: from the hook (or the fish's mouth) up to the float or to the surface, then on
        // up through the film toward the rod, fainter above the water.
        let lineColor = tint(NSColor(white: 0.95, alpha: 0.78))
        line.strokeColor = lineColor
        airLine.strokeColor = tint(NSColor(white: 0.9, alpha: 0.22))
        line.zPosition = layer - 0.001; airLine.zPosition = layer - 0.001
        let path = CGMutablePath(), air = CGMutablePath()
        let start = eye
        let slack = r.phase == .fighting ? max(0, 1 - r.pressure * 5) : (r.offering.usesFloat || r.speed > 0.004 || r.holderID != nil ? 0 : 0.6)
        // The line jumps as a fish takes, and twangs for a moment while it settles taut.
        // Under water the lure's line kicks harder and stays bowed toward the fish while it holds.
        let sunkLure = r.offering.isLure && !r.offering.floats
        let jump = r.takeAge < 0.8 ? CGFloat(sin(r.takeAge * 46) * exp(-r.takeAge * 6) * (sunkLure ? 18 : 7) * scale) : 0
        let holdingLure = sunkLure && r.holderID != nil
        let shake = holdingLure && r.takeAge < 0.5 ? sin(r.takeAge * 2 * .pi * 6) * 4 : 0
        let bow = holdingLure ? CGFloat(r.takeSide * (28 * min(1, r.takeAge / 0.15) + shake) * scale) : 0
        if r.phase == .flying {
            air.move(to: tip); air.addLine(to: rig)
        } else if showFloat {
            path.move(to: start)
            // On a lift the fish has taken the shot's weight, and the line between goes slack.
            // It hangs in a loose bend just under the float, where the weight came off.
            let lifted = (-r.floatDip / 0.3).clamped(to: 0...1)
            let along = 0.5 + 0.35 * lifted
            let mid = CGPoint(x: start.x + (floatFoot.x - start.x) * CGFloat(along) + CGFloat(slack * 8 * scale + lifted * 22 * scale) + jump,
                              y: start.y + (floatFoot.y - start.y) * CGFloat(along))
            path.addQuadCurve(to: floatFoot, control: mid)
            air.move(to: floatTop); air.addLine(to: tip)
        } else {
            // Where the straight line to the rod tip meets the surface.
            let t = (surface - start.y) / max(1, tip.y - start.y)
            let entry = CGPoint(x: start.x + (tip.x - start.x) * t, y: surface)
            let sag = CGFloat(slack * 0.06) * (framing.imageRect.height)
            let control = CGPoint(x: (start.x + entry.x) / 2 + jump + bow, y: (start.y + entry.y) / 2 - sag)
            path.move(to: start); path.addQuadCurve(to: entry, control: control)
            air.move(to: entry); air.addLine(to: tip)
        }
        line.path = path
        airLine.path = air
        // Two split shot pinched on the line, which sink the bait and cock the float.
        for (i, shot) in shotNodes.enumerated() {
            shot.isHidden = !showFloat || inMouth
            let along = i == 0 ? 0.62 : 0.74
            shot.position = CGPoint(x: floatFoot.x + (start.x - floatFoot.x) * along, y: floatFoot.y + (start.y - floatFoot.y) * along)
            shot.size = CGSize(width: 4.2 * scale, height: 4.2 * scale)
            shot.color = tint(NSColor(white: 0.28, alpha: 1))
            shot.zPosition = layer
        }
        line.lineWidth = CGFloat(max(1, 1.4 * scale))

        // Splash: rings spreading on the film and a few bubbles dragged down by the rig.
        let entryPoint = point(r.castX, r.surfaceY)
        for (i, ring) in rings.enumerated() {
            let age = r.splashAge - Double(i) * 0.18
            // Rings spread from a pecked float, and from a fish rising to take a dry fly.
            let rise = r.offering.floats && r.holderID == nil && r.floatBob > 0.08
            let peck = (showFloat && r.floatBob > 0.08) || rise
            let ringAge = peck ? (r.bobClock * 1.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1) : age
            let active = peck || (age > 0 && age < 1.6)
            guard active else { ring.isHidden = true; continue }
            let radius = (peck ? (rise ? 8 + ringAge * 30 : 6 + ringAge * 18) : 8 + age * 46) * scale
            let strength = rise ? 0.8 : min(1, r.floatBob * 2)
            styleRing(ring, radius: radius, at: peck ? CGPoint(x: rise ? point(r.x, r.surfaceY).x : floatBase.x, y: surface) : entryPoint,
                      alpha: peck ? (1 - ringAge) * 0.75 * strength : max(0, 1 - age / 1.6) * 0.7, night: night, z: layer + 0.02)
        }
        for (i, bubble) in splashBubbles.enumerated() {
            let age = r.splashAge - Double(i) * 0.03
            let life = 1.1 + Double(i % 4) * 0.25
            let active = age > 0 && age < life && !r.offering.floats
            bubble.isHidden = !active
            guard active else { continue }
            let spread = (Double(i) * 0.6180339).truncatingRemainder(dividingBy: 1) - 0.5
            let down = min(age, 0.35) * 70 - max(0, age - 0.35) * 30
            bubble.position = CGPoint(x: entryPoint.x + CGFloat(spread * 22 * scale + sin(age * 9 + Double(i)) * 2), y: entryPoint.y - CGFloat(max(0, down) * scale))
            let d = (2 + Double(i % 3) * 1.6) * scale
            bubble.size = CGSize(width: d, height: d)
            bubble.alpha = CGFloat(0.75 * (1 - age / life))
            bubble.zPosition = layer + 0.01
        }
        // A take on the film: a dent where the float was pulled through or the fly sipped down,
        // one ring spreading from it and a fainter one after.
        let onFilm = r.offering.usesFloat || r.offering.floats
        let fly = r.offering.floats
        let origin = point(r.takeX, r.surfaceY)
        let big = fly ? 0.9 : min(1, 0.55 + max(0, r.floatDip) * 0.6)
        let filmTake = onFilm && !(r.biteStyle == .lift && r.offering.usesFloat && r.holderID != nil && r.floatDip < 0.2)
        for (i, ring) in takeRings.enumerated() {
            // A lift slaps the float flat (a small ring), then goes under (the main one). A rise
            // holds its dimple a moment before the ring spreads.
            let lifting = r.biteStyle == .lift && !fly
            let age = r.takeAge - (i == 0 ? (lifting ? 0.9 : (fly ? 0.3 : 0)) : (lifting ? 0.12 : (fly ? 0.5 : 0.22)))
            let slap = lifting && i == 1
            let active = (filmTake || slap) && age > 0 && age < 1.5
            guard active else { ring.isHidden = true; continue }
            // Fast at first, then slowing as the ring spreads and flattens out.
            let spread = 1 - exp(-age * 2.2)
            styleRing(ring, radius: ((fly ? 12 : 6) + spread * 70 * big) * scale, flat: 0.2, at: origin,
                      alpha: pow(1 - age / 1.5, 1.2) * (slap ? 0.7 : (i == 0 ? 1 : 0.45) * big), night: night, z: layer + 0.02)
        }
        let dentAge = r.takeAge - (r.biteStyle == .lift && !fly ? 0.9 : 0)
        let dentLife = fly ? 0.75 : 0.5
        dent.isHidden = !(filmTake && dentAge > 0 && dentAge < dentLife)
        if !dent.isHidden {
            // A rise leaves a deep dimple that holds a moment, then fills in as the ring spreads.
            let width = (fly ? 56 : 18) * scale * (fly ? 1 + max(0, dentAge - 0.3) * 1.2 : 0.7 + dentAge)
            dent.size = CGSize(width: width, height: width * (fly ? 0.38 : 0.32))
            dent.position = CGPoint(x: origin.x, y: surface - CGFloat(1.5 * scale))
            // Darker than the film around it, so it reads even on the brightest band of light.
            dent.alpha = CGFloat((fly ? 1 : 0.55) * min(1, (1 - dentAge / dentLife) * (fly ? 1.4 : 1)) * (1 - night * 0.4))
            dent.zPosition = layer + 0.011
            if fly {
                // Its bright lip.
                collar.isHidden = false
                collar.size = CGSize(width: width * 1.05, height: width * 0.36)
                collar.position = CGPoint(x: origin.x, y: surface)
                collar.alpha = CGFloat(0.45 * (1 - dentAge / dentLife) * (1 - night * 0.5))
            }
        }
        // A fly sipped down leaves one bubble on the film; a float sailed off sheds a couple
        // from its tip. Nothing else carries air down.
        for (i, bubble) in takeBubbles.enumerated() {
            let sailing = r.offering.usesFloat && r.biteStyle == .sailAway && i < 2
            let birth = fly ? 0.12 : 0.05 + Double(i) * 0.14
            let age = r.takeAge - birth
            let life = fly ? 1.4 : 0.8
            let active = (fly ? i == 0 : sailing) && age > 0 && age < life
            bubble.isHidden = !active
            guard active else { continue }
            let from = fly ? CGPoint(x: origin.x + CGFloat(4 * scale), y: surface - CGFloat(3 * scale)) : floatTop
            let rise = CGFloat(age * 60 * scale)
            bubble.position = CGPoint(x: from.x + CGFloat(sin(age * 9 + Double(i)) * 1.5 * scale), y: min(surface - CGFloat(2 * scale), from.y + rise))
            let d = (fly ? 5.5 : 3.5) * scale
            bubble.size = CGSize(width: d, height: d)
            bubble.alpha = CGFloat(min(1, (1 - age / life) * 2) * (1 - night * 0.4))
            bubble.zPosition = layer + 0.015
        }
        // A lure hit under water: a flash of silver flank as the fish turns on it.
        let flashAge = r.takeAge
        flash.isHidden = !(sunkLure && flashAge < 0.09 && r.holderID != nil)
        if !flash.isHidden {
            // A thin streak along the flank as the fish turns broadside on the lure.
            flash.size = CGSize(width: 54 * scale, height: 8 * scale)
            flash.position = CGPoint(x: rig.x - CGFloat(r.takeSide * 20 * scale), y: rig.y)
            flash.zRotation = CGFloat(r.takeSide > 0 ? 0.12 : -0.12)
            flash.alpha = CGFloat((1 - flashAge / 0.09) * (1 - night * 0.5))
            flash.zPosition = layer + 0.02
        }
        for (i, node) in crumbNodes.enumerated() {
            guard r.crumbs.indices.contains(i) else { node.isHidden = true; continue }
            let crumb = r.crumbs[i]
            node.isHidden = false
            node.position = point(crumb.x, crumb.y)
            let d = (1.6 + crumb.size * 1.8) * scale
            node.size = CGSize(width: d, height: d)
            node.color = tint(r.offering == .pellet ? NSColor(srgbRed: 0.55, green: 0.36, blue: 0.2, alpha: 1) : NSColor(srgbRed: 0.95, green: 0.92, blue: 0.84, alpha: 1))
            node.alpha = CGFloat(max(0, 1 - crumb.age / 7) * 0.85)
            node.zPosition = layer + 0.001
        }
    }
}
