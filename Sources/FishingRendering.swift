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
    private var rings: [SKShapeNode] = []
    private var splashBubbles: [SKSpriteNode] = []
    private var crumbNodes: [SKSpriteNode] = []
    private let tipGlow = SKSpriteNode(texture: Artwork.softDot)
    private let cue = SKShapeNode()
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
        cue.fillColor = .clear
        cue.lineWidth = 3.5
        addChild(cue)
        for _ in 0..<2 {
            let shot = SKSpriteNode(texture: Artwork.mote)
            shot.colorBlendFactor = 1
            addChild(shot); shotNodes.append(shot)
        }
        for _ in 0..<3 {
            let ring = SKShapeNode(ellipseOf: CGSize(width: 10, height: 2))
            ring.fillColor = .clear
            ring.lineWidth = 1.6
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
            floatBase.y += CGFloat(ripple + bob - r.floatDip * floatHeight * 0.75)
            floatNode.size = CGSize(width: floatHeight * 0.25, height: floatHeight)
            // A float lies flat until the sinking shot cocks it upright; a fish taking the bait on
            // the drop leaves it lying there, the sign anglers watch for.
            var cock = 1.0
            if r.phase == .sinking {
                let fallen = ((r.surfaceY - r.y) / max(0.01, r.surfaceY - r.setDepthY)).clamped(to: 0...1)
                let t = ((fallen - 0.55) / 0.45).clamped(to: 0...1)
                cock = t * t * (3 - 2 * t)
            }
            // The line from the bait drags the foot toward it.
            let lean = r.floatDip * 0.5 * (r.x < r.floatX ? -1 : 1) + sin(r.bobClock * 1.3) * 0.04
            let angle = lean * cock - .pi / 2 * (1 - cock)
            // The waterline sits at 62% of the float's height, so a cocked float shows its tip.
            let waterline = floatHeight * 0.12 * cock
            floatNode.position = CGPoint(x: floatBase.x + CGFloat(waterline * sin(angle)), y: floatBase.y - CGFloat(waterline * cos(angle)))
            floatNode.zRotation = CGFloat(angle)
            floatNode.zPosition = layer + 0.01
            floatNode.color = tint(.white); floatNode.colorBlendFactor = CGFloat(night * 0.6)
        }
        let floatAngle = Double(floatNode.zRotation)
        let floatFoot = CGPoint(x: floatNode.position.x + CGFloat(sin(floatAngle) * floatHeight * 0.5),
                                y: floatNode.position.y - CGFloat(cos(floatAngle) * floatHeight * 0.5))
        let floatTop = CGPoint(x: floatNode.position.x - CGFloat(sin(floatAngle) * floatHeight * 0.5),
                               y: floatNode.position.y + CGFloat(cos(floatAngle) * floatHeight * 0.5))
        // A glow-stick tip at night, and an orange pulse when a fish has the bait and it is time to strike.
        // A dry fly at night catches a glint of moonlight on the film.
        let flyGlint = r.offering.floats && r.inWater && r.holderID == nil
        tipGlow.isHidden = !(showFloat || flyGlint) || night < 0.15
        tipGlow.position = showFloat ? CGPoint(x: floatTop.x + (floatFoot.x - floatTop.x) * 0.12, y: floatTop.y + (floatFoot.y - floatTop.y) * 0.12) : rig
        tipGlow.size = CGSize(width: (showFloat ? 22 : 16) * scale, height: (showFloat ? 22 : 10) * scale)
        tipGlow.color = showFloat ? NSColor(srgbRed: 1, green: 0.62, blue: 0.2, alpha: 1) : NSColor(srgbRed: 0.75, green: 0.85, blue: 1, alpha: 1)
        tipGlow.alpha = CGFloat(min(1, night * 1.1) * (showFloat ? 1 - r.floatDip * 0.6 : 0.55))
        tipGlow.zPosition = layer + 0.02
        // Strike now: an orange pulse on the float, or where a fish has hit the fly or lure.
        let strikeCue = r.holderID != nil && !r.hook.setsItself && (showFloat || r.offering.isLure)
        cue.isHidden = !strikeCue
        if strikeCue {
            let pulse = 0.5 + 0.5 * sin(r.bobClock * 12)
            let radius = (16 + pulse * 8) * scale
            // On the film (float, fly) the ring lies flat as the surface does; around a lure under water it is round.
            let onFilm = showFloat || r.offering.floats
            cue.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius * (onFilm ? 0.25 : 0.5), width: radius * 2, height: radius * (onFilm ? 0.5 : 1)), transform: nil)
            cue.position = showFloat ? CGPoint(x: floatBase.x, y: point(r.floatX, r.surfaceY).y) : (r.offering.floats ? CGPoint(x: rig.x, y: point(r.x, r.surfaceY).y) : rig)
            cue.strokeColor = NSColor(srgbRed: 1, green: 0.45, blue: 0.15, alpha: CGFloat(0.55 + 0.4 * pulse))
            cue.zPosition = layer + 0.03
        }

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
        let slack = r.phase == .fighting ? max(0, 1 - r.pressure * 5) : (r.offering.usesFloat || r.speed > 0.004 ? 0 : 0.6)
        if r.phase == .flying {
            air.move(to: tip); air.addLine(to: rig)
        } else if showFloat {
            path.move(to: start)
            let mid = CGPoint(x: (start.x + floatFoot.x) / 2 + CGFloat(slack * 8 * scale), y: (start.y + floatFoot.y) / 2)
            path.addQuadCurve(to: floatFoot, control: mid)
            air.move(to: floatTop); air.addLine(to: tip)
        } else {
            // Where the straight line to the rod tip meets the surface.
            let t = (surface - start.y) / max(1, tip.y - start.y)
            let entry = CGPoint(x: start.x + (tip.x - start.x) * t, y: surface)
            let sag = CGFloat(slack * 0.06) * (framing.imageRect.height)
            let control = CGPoint(x: (start.x + entry.x) / 2, y: (start.y + entry.y) / 2 - sag)
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
            let rise = r.offering.floats && (r.holderID != nil || r.floatBob > 0.08)
            let peck = (showFloat && r.floatBob > 0.08) || rise
            let ringAge = peck ? (r.bobClock * 1.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1) : age
            let active = peck || (age > 0 && age < 1.6)
            ring.isHidden = !active
            guard active else { continue }
            let radius = (peck ? (rise ? 8 + ringAge * 30 : 6 + ringAge * 18) : 8 + age * 46) * scale
            ring.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius * 0.16, width: radius * 2, height: radius * 0.32), transform: nil)
            ring.position = peck ? CGPoint(x: rise ? point(r.x, r.surfaceY).x : floatBase.x, y: surface) : entryPoint
            let strength = rise ? 0.8 : min(1, r.floatBob * 2)
            ring.strokeColor = tint(NSColor(white: 1, alpha: CGFloat(peck ? (1 - ringAge) * 0.45 * strength : max(0, 1 - age / 1.6) * 0.55)))
            ring.zPosition = layer + 0.02
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
