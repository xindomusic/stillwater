import AppKit
import SpriteKit

/// Attribute values are reused every frame instead of allocating new ones per node.
private final class FishSprite: SKSpriteNode {
    let depthValue = SKAttributeValue(float: 1)
    let poseValue = SKAttributeValue(float: 0)
    let phaseValue = SKAttributeValue(float: 0)
    let strokeValue = SKAttributeValue(vectorFloat4: .zero)
    let finsValue = SKAttributeValue(vectorFloat4: .zero)
    let curveValue = SKAttributeValue(vectorFloat4: .zero)
}

private final class PelletSprite: SKSpriteNode {
    let depthValue = SKAttributeValue(float: 1)
    let tumbleValue = SKAttributeValue(float: 0)
    let rollValue = SKAttributeValue(float: 0)
    let seedValue = SKAttributeValue(float: 0)
    let edgeValue = SKAttributeValue(float: 0)
}

private final class BubbleSprite: SKSpriteNode {
    let depthValue = SKAttributeValue(float: 1)
    let waterRectValue = SKAttributeValue(vectorFloat4: .zero)
    let edgeValue = SKAttributeValue(float: 0)
}

final class AquariumScene: SKScene {
    private(set) var configuration: AquariumConfiguration
    private(set) var simulation = AquariumSimulation()
    private(set) var frameCount = 0
    private let backdrop = SKSpriteNode()
    private let shade = SKSpriteNode(color: .black, size: .zero)
    private var fishNodes: [Int: FishSprite] = [:]
    private var foodNodes: [Int: PelletSprite] = [:]
    private var fishShadows: [Int: SKSpriteNode] = [:]
    private var framing: AquariumFraming?
    // Sprites share one texture and batch into a single GPU draw; shape nodes would be
    // tessellated on the CPU and drawn one by one.
    private var motes: [SKSpriteNode] = []
    private var bubbleNodes: [BubbleSprite] = []
    private var sandNodes: [SKSpriteNode] = []
    private var airStoneNodes: [SKSpriteNode] = []
    private var airStoneShadows: [SKSpriteNode] = []
    private var airStoneMounds: [SKSpriteNode] = []
    private var previousTime: TimeInterval?
    private(set) var nightAmount = 0.0
    private(set) var systemIsDark = false
    private var nightTarget = 0.0
    private let backgroundShader = SKShader(source: WaterRendering.shaderSource)
    private let fishShader: SKShader = {
        let shader = FishRendering.makeShader()
        shader.uniformNamed("u_canvas")?.floatValue = Float(AquariumScene.fishCanvas)
        return shader
    }()
    private let bubbleShader = BubbleRendering.makeShader()
    private let pelletShader = PelletRendering.makeShader()
    private var appliedNight = -1.0

    init(size: CGSize, configuration: AquariumConfiguration) {
        self.configuration = configuration
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = NSColor(rgb: 0x101722)
        backgroundShader.uniforms = [SKUniform(name: "u_clock", float: 0), SKUniform(name: "u_sway", float: 0.55), SKUniform(name: "u_shimmer", float: 0.35), SKUniform(name: "u_brightness", float: 1), SKUniform(name: "u_night", float: 0), SKUniform(name: "u_regions", texture: Artwork.motionRegions(configuration.theme))]
        backdrop.shader = backgroundShader
        backdrop.zPosition = -100
        addChild(backdrop)
        shade.zPosition = 100
        shade.alpha = 0
        addChild(shade)
        for i in 0..<36 {
            let diameter: CGFloat = i % 4 == 0 ? 2.2 : 1.3
            let dot = SKSpriteNode(texture: Artwork.mote, size: CGSize(width: diameter, height: diameter))
            dot.colorBlendFactor = 1
            dot.color = NSColor(rgb: 0xe6effa)
            dot.alpha = 0.18
            dot.zPosition = CGFloat(i % 3) + 15
            addChild(dot); motes.append(dot)
        }
        for i in 0..<BubbleField.maximumBubbles {
            let bubble = BubbleSprite()
            bubble.name = "bubble-\(i)"
            bubble.shader = bubbleShader
            bubble.zPosition = 20
            addChild(bubble); bubbleNodes.append(bubble)
        }
        for i in 0..<SandField.maximumGrains {
            let grain = SKSpriteNode(texture: Artwork.mote)
            grain.name = "sand-\(i)"
            grain.colorBlendFactor = 1
            grain.isHidden = true
            addChild(grain); sandNodes.append(grain)
        }
        apply(configuration, force: true)
    }
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didChangeSize(_ oldSize: CGSize) { layoutBackdrop(); positionContents() }
    /// Points per unit of `FishSpecies.bodySize`; artwork is authored for a 900-point-tall scene.
    /// Distance from the sprite's centre to the turning pivot, as a share of the sprite.
    static let turnPivot = 0.15
    static func bedLift(_ depth: Double) -> Double { AquariumSimulation.bedLift(depth) }

    /// Fish sprites are drawn larger than the fish so a deeply bent tail stays inside them.
    static let fishCanvas = 1.5

    private var artworkScale: Double { max(0.1, (framing?.imageRect.height ?? size.height) / 900) }

    private func layoutBackdrop() {
        guard let texture = backdrop.texture, size.width > 0, size.height > 0 else { return }
        let layout = AquariumFraming(viewport: size, image: texture.size())
        framing = layout
        backdrop.size = layout.imageRect.size
        backdrop.position = CGPoint(x: layout.imageRect.midX, y: layout.imageRect.midY)
        simulation.visibleRegion = layout.visibleRegion
        simulation.synchronize(configuration)
        shade.size = size
        shade.position = backdrop.position
    }

    func apply(_ next: AquariumConfiguration, force: Bool = false) {
        let changedScene = next.theme != configuration.theme || force
        configuration = next
        resolveLighting(immediate: force)
        if changedScene {
            backdrop.texture = Artwork.sceneTexture(next.theme)
            backgroundShader.uniformNamed("u_regions")?.textureValue = Artwork.motionRegions(next.theme)
            bubbleNodes.forEach { $0.texture = backdrop.texture }
            layoutBackdrop()
        }
        backgroundShader.uniformNamed("u_sway")?.floatValue = Float(next.plantSway)
        backgroundShader.uniformNamed("u_shimmer")?.floatValue = Float(next.shimmer)
        backgroundShader.uniformNamed("u_brightness")?.floatValue = Float(next.brightness)
        fishShader.uniformNamed("u_brightness")?.floatValue = Float(min(1.15, next.brightness) * 0.95)
        bubbleShader.uniformNamed("u_brightness")?.floatValue = Float(next.brightness)
        pelletShader.uniformNamed("u_brightness")?.floatValue = Float(next.brightness)
        simulation.synchronize(next)
        let liveIDs = Set(simulation.fish.map(\.id))
        for id in Array(fishNodes.keys) where !liveIDs.contains(id) {
            fishNodes.removeValue(forKey: id)?.removeFromParent()
            fishShadows.removeValue(forKey: id)?.removeFromParent()
        }
        for fish in simulation.fish where fishNodes[fish.id] == nil {
            let node = FishSprite(texture: Artwork.fishTexture(fish.species))
            node.name = "fish-\(fish.id)"
            node.shader = fishShader
            node.setValue(SKAttributeValue(float: fish.species.renderingKind), forAttribute: "a_species")
            node.setValue(SKAttributeValue(vectorFloat2: Artwork.fishSampleScale(fish.species)), forAttribute: "a_sampleScale")
            node.setValue(SKAttributeValue(vectorFloat2: Artwork.fishVisibleY(fish.species)), forAttribute: "a_visibleY")
            node.setValue(SKAttributeValue(vectorFloat4: Artwork.fishProfileRect), forAttribute: "a_rect0")
            addChild(node); fishNodes[fish.id] = node
            if fish.species.isBottomDweller {
                let shadow = SKSpriteNode(texture: Artwork.contactShadow)
                shadow.zPosition = 4
                addChild(shadow); fishShadows[fish.id] = shadow
            }
        }
        motes.forEach { $0.isHidden = !next.particles }
        bubbleNodes.forEach { $0.isHidden = !next.bubbles }
        previousTime = nil
        positionContents()
    }

    func setSystemDark(_ dark: Bool, immediate: Bool = false) {
        systemIsDark = dark
        resolveLighting(immediate: immediate)
        positionContents()
    }
    private func resolveLighting(immediate: Bool) {
        nightTarget = configuration.lightingMode.isNight(systemIsDark: systemIsDark) ? 1 : 0
        if immediate || configuration.mode == .still { nightAmount = nightTarget }
    }
    private var swimmingConfiguration: AquariumConfiguration {
        var config = configuration
        config.swimmingSpeed *= 1 - nightAmount * 0.28
        return config
    }

    func feed() { simulation.feed(configuration); positionContents() }

    func resetClock() { previousTime = nil }

    override func update(_ currentTime: TimeInterval) {
        frameCount += 1
        defer { previousTime = currentTime }
        guard let previousTime, configuration.mode == .live else { return }
        let dt = max(0, min(0.1, currentTime - previousTime))
        nightAmount += (nightTarget - nightAmount) * (1 - exp(-dt * 1.4))
        if abs(nightTarget - nightAmount) < 0.001 { nightAmount = nightTarget }
        simulation.step(delta: currentTime - previousTime, configuration: swimmingConfiguration)
        positionContents()
    }

    private func positionContents() {
        let clock = simulation.time
        if appliedNight != nightAmount {
            for shader in [backgroundShader, fishShader, bubbleShader, pelletShader] { shader.uniformNamed("u_night")?.floatValue = Float(nightAmount) }
            appliedNight = nightAmount
        }
        backgroundShader.uniformNamed("u_clock")?.floatValue = Float(clock)
        let scale = artworkScale
        for f in simulation.fish {
            guard let node = fishNodes[f.id] else { continue }
            // Depth changes during turns, so size, layering, and water tint follow it every frame.
            let body = f.species.bodySize * f.depth * scale
            node.size = CGSize(width: body * Self.fishCanvas, height: body * Self.fishCanvas)
            node.zPosition = CGFloat(ParticlePerspective.layer(f.depth))
            node.depthValue.floatValue = Float(f.depth); node.setValue(node.depthValue, forAttribute: "a_depth")
            // A fish turns about a point in the front third of its body, so the tail swings wider
            // than the head; the simulated position is that pivot.
            let pivot = framing?.point(x: f.x, y: f.y) ?? CGPoint(x: f.x * size.width, y: f.y * size.height)
            let pivotOffset = f.species.isInvertebrate ? 0 : cos(f.yaw) * body * Self.turnPivot
            let bedLift = f.species.isBottomDweller ? Self.bedLift(f.depth) * (framing?.imageRect.height ?? size.height) : 0
            node.position = CGPoint(x: pivot.x - CGFloat(pivotOffset), y: pivot.y + CGFloat(bedLift))
            let wrappedYaw = (f.yaw.truncatingRemainder(dividingBy: 2 * .pi) + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
            let pose = wrappedYaw / (.pi / 4)
            node.poseValue.floatValue = Float(pose); node.setValue(node.poseValue, forAttribute: "a_pose")
            node.phaseValue.floatValue = Float(f.finPhase); node.setValue(node.phaseValue, forAttribute: "a_finPhase")
            node.strokeValue.vectorFloat4Value = SIMD4(Float(f.stroke.amplitude), Float(f.stroke.bend),
                f.species == .shrimp ? Float(f.shrimpBehavior.concealment) : 0,
                f.species == .shrimp && f.shrimpBehavior.coverOnLeft ? 1 : 0)
            node.setValue(node.strokeValue, forAttribute: "a_stroke")
            node.finsValue.vectorFloat4Value = SIMD4(Float(f.stroke.pectoralPhase), Float(f.stroke.dorsalPhase), Float(f.stroke.spread), Float(f.stroke.finAmplitude))
            node.setValue(node.finsValue, forAttribute: "a_fins")
            var curve = f.spineCurve
            if f.species == .shrimp && f.shrimpBehavior.isEscaping {
                // Fourth component: how far the shrimp's abdomen is folded in a tail flip.
                let behavior = f.shrimpBehavior
                let withinFlip = (behavior.escapeDuration - behavior.escapeRemaining).truncatingRemainder(dividingBy: ShrimpBehavior.flipDuration) / ShrimpBehavior.flipDuration
                curve.w = Float(sin(withinFlip * .pi))
            }
            node.curveValue.vectorFloat4Value = curve; node.setValue(node.curveValue, forAttribute: "a_curve")
            let bite: Double
            if !f.species.isInvertebrate, let response = f.feeding, response.phase == .nibbling {
                let envelope = min(1, response.age * 6) * min(1, max(0, response.remaining) * 6)
                bite = sin(response.age * 18) * 0.045 * envelope
            } else { bite = 0 }
            // A shrimp sinking back after a flip tips nose-down.
            let sinking = f.species == .shrimp && !f.shrimpBehavior.isEscaping && f.vy < -TankScale.height(cm: 0.5) ? -0.25 : 0.0
            node.zRotation = CGFloat((f.pitch + bite + sinking) * cos(f.yaw))
            // Distance changes color, never the opacity of a fish's body.
            if let shadow = fishShadows[f.id] {
                shadow.size = CGSize(width: body * 0.72, height: body * 0.08)
                shadow.position = CGPoint(x: node.position.x, y: node.position.y - body * (f.species.isInvertebrate ? 0.25 : 0.085))
                shadow.alpha = f.species == .shrimp ? 1 - f.shrimpBehavior.concealment : 1
                if f.species == .shrimp {
                    let bedTop = AquariumSimulation.region(for: .loach, theme: configuration.theme).top
                    if f.y > bedTop {
                        shadow.position.y -= (f.y - bedTop) * (framing?.imageRect.height ?? size.height)
                        shadow.alpha *= max(0, 1 - (f.y - bedTop) / 0.065)
                    }
                }
            }
        }
        let pelletIDs = Set(simulation.food.map(\.id))
        for id in Array(foodNodes.keys) where !pelletIDs.contains(id) { foodNodes.removeValue(forKey: id)?.removeFromParent() }
        for pellet in simulation.food {
            let node: PelletSprite
            if let existing = foodNodes[pellet.id] { node = existing }
            else {
                node = PelletSprite(color: .white, size: .zero)
                node.name = "pellet-\(pellet.id)"
                node.shader = pelletShader
                addChild(node); foodNodes[pellet.id] = node
            }
            node.position = framing?.point(x: pellet.x, y: pellet.y) ?? .zero
            // Community micro-pellets of about 0.8 to 1.6 mm, smaller and softer farther back.
            let millimetres = 0.8 + (pellet.size - 0.65) * 1.6
            let imageHeight = framing?.imageRect.height ?? size.height
            let diameter = max(2.2, TankScale.points(mm: millimetres, imageHeight: imageHeight) * ParticlePerspective.scale(pellet.depth))
            node.size = CGSize(width: diameter, height: diameter)
            node.zPosition = ParticlePerspective.layer(pellet.depth)
            node.alpha = CGFloat(min(1, (70 - pellet.age) / 4))
            node.depthValue.floatValue = Float(pellet.depth); node.setValue(node.depthValue, forAttribute: "a_depth")
            node.tumbleValue.floatValue = Float(pellet.tumble); node.setValue(node.tumbleValue, forAttribute: "a_tumble")
            node.rollValue.floatValue = Float(pellet.rotation); node.setValue(node.rollValue, forAttribute: "a_roll")
            node.seedValue.floatValue = Float(pellet.phase); node.setValue(node.seedValue, forAttribute: "a_seed")
            let pelletEdge = (1 + ParticlePerspective.blur(pellet.depth)) / max(1, diameter / 2)
            node.edgeValue.floatValue = Float(min(0.6, pelletEdge)); node.setValue(node.edgeValue, forAttribute: "a_edge")
        }
        for (i, dot) in motes.enumerated() where configuration.particles {
            let n = Double(i)
            let x = (n * 0.6180339 + sin(clock * 0.08 + n) * 0.012).truncatingRemainder(dividingBy: 1)
            let y = (n * 0.381966 + clock * 0.003).truncatingRemainder(dividingBy: 1)
            dot.position = CGPoint(x: (x < 0 ? x + 1 : x) * size.width, y: y * size.height)
            dot.setScale(scale)
        }
        let imageHeight = framing?.imageRect.height ?? size.height
        let imageSize = framing?.imageRect.size ?? size
        for (i, bubble) in bubbleNodes.enumerated() where configuration.bubbles {
            guard simulation.bubbles.indices.contains(i) else { bubble.alpha = 0; continue }
            let state = simulation.bubbles[i]
            bubble.position = framing?.point(x: state.x, y: state.y) ?? .zero
            // Pops at the surface; appears as it detaches.
            let top = simulation.visibleRegion.top
            bubble.alpha = CGFloat(min(1, state.age * 20) * min(1, max(0, top - state.y) * 40))
            // Never smaller than a visible speck, so the fine mist still reads.
            let diameter = max(2.5, TankScale.points(mm: state.diameter, imageHeight: imageHeight) * BubbleField.displayScale * ParticlePerspective.scale(state.depth))
            bubble.zPosition = ParticlePerspective.layer(state.depth)
            bubble.depthValue.floatValue = Float(state.depth); bubble.setValue(bubble.depthValue, forAttribute: "a_depth")
            // Larger bubbles are flattened and rock as they zigzag; volume stays the same.
            let rocking = state.zigzagAmplitude > 0 ? 1 + 0.08 * sin(4 * .pi * state.zigzagFrequency * state.age + state.phase) : 1
            let aspect = state.aspect * rocking
            bubble.size = CGSize(width: diameter * pow(aspect, 1.0 / 3), height: diameter / pow(aspect, 2.0 / 3))
            let w = Float(bubble.size.width / imageSize.width), h = Float(bubble.size.height / imageSize.height)
            bubble.waterRectValue.vectorFloat4Value = SIMD4(Float(state.x) - w / 2, Float(state.y) - h / 2, w, h)
            bubble.setValue(bubble.waterRectValue, forAttribute: "a_waterRect")
            let bubbleEdge = (1 + ParticlePerspective.blur(state.depth)) / max(1, diameter / 2)
            bubble.edgeValue.floatValue = Float(min(0.6, bubbleEdge)); bubble.setValue(bubble.edgeValue, forAttribute: "a_edge")
        }
        let stones = simulation.bubbleField.sources.filter { $0.kind == .airStone }
        while airStoneNodes.count < stones.count {
            let node = SKSpriteNode(texture: Artwork.airStone)
            node.name = "air-stone-\(airStoneNodes.count)"
            addChild(node); airStoneNodes.append(node)
            let shadow = SKSpriteNode(texture: Artwork.contactShadow)
            addChild(shadow); airStoneShadows.append(shadow)
            let mound = SKSpriteNode(texture: Artwork.airStoneMound)
            mound.colorBlendFactor = 1
            addChild(mound); airStoneMounds.append(mound)
        }
        for (i, node) in airStoneNodes.enumerated() {
            guard configuration.bubbles, stones.indices.contains(i) else {
                node.isHidden = true; airStoneShadows[i].isHidden = true; airStoneMounds[i].isHidden = true; continue
            }
            let stone = stones[i]
            let length = TankScale.points(mm: 20, imageHeight: imageHeight) * ParticlePerspective.scale(stone.depth)
            node.isHidden = false
            node.size = CGSize(width: length, height: length * 56 / 128)
            node.position = framing?.point(x: stone.x, y: stone.y) ?? .zero
            // Bedded in: the lower part of the stone sits below the sand line, under the mound.
            node.position.y -= node.size.height * 0.2
            node.zPosition = ParticlePerspective.layer(stone.depth) - 0.001
            node.color = NSColor(rgb: 0x33403f)
            node.colorBlendFactor = CGFloat(0.12 + nightAmount * 0.4)
            let shadow = airStoneShadows[i]
            shadow.isHidden = false
            shadow.size = CGSize(width: node.size.width * 1.15, height: node.size.height * 0.45)
            shadow.position = CGPoint(x: node.position.x, y: node.position.y - node.size.height * 0.05)
            shadow.alpha = 0.6
            shadow.zPosition = node.zPosition - 0.0005
            // Sand in the scene's own colour, heaped against the stone's base.
            let mound = airStoneMounds[i]
            mound.isHidden = false
            mound.size = CGSize(width: node.size.width * 1.35, height: node.size.height * 0.6)
            mound.position = CGPoint(x: node.position.x, y: node.position.y - node.size.height * 0.25)
            mound.zPosition = node.zPosition + 0.0005
            let sand = Artwork.sandColor(configuration.theme, x: stone.x, y: stone.y)
            mound.color = nightAmount > 0.5 ? sand.blended(withFraction: 0.55, of: NSColor(rgb: 0x2c3444)) ?? sand : sand
        }
        let grains = simulation.sand.grains
        // Stirred sand: grains a little darker than the lit bed, silt a pale beige haze.
        // Grains a shade darker than the local sand, silt a touch lighter; darker still at night.
        let night = CGFloat(nightAmount)
        func shade(_ color: NSColor, _ factor: CGFloat) -> NSColor {
            let c = color.usingColorSpace(.sRGB) ?? color
            let dim = factor * (1 - night * 0.55)
            return NSColor(srgbRed: min(1, c.redComponent * dim), green: min(1, c.greenComponent * dim), blue: min(1, c.blueComponent * dim * (1 + night * 0.15)), alpha: 1)
        }
        for (i, node) in sandNodes.enumerated() {
            guard grains.indices.contains(i) else { node.isHidden = true; continue }
            let grain = grains[i]
            node.isHidden = false
            node.texture = grain.isCloud ? Artwork.softDot : Artwork.sandGrains[i % Artwork.sandGrains.count]
            let localSand = Artwork.sandColor(configuration.theme, x: (grain.x * 20).rounded() / 20, y: 0.07)
            node.color = grain.isCloud ? shade(localSand, 1.02) : shade(localSand, [0.8, 0.86, 0.74][(i / 4) % 3])
            node.zRotation = grain.isCloud ? 0 : CGFloat(i) * 1.37
            node.position = framing?.point(x: grain.x, y: grain.y) ?? .zero
            node.position.y += CGFloat(Self.bedLift(grain.depth) * imageHeight)
            let diameter = max(1.2, TankScale.points(mm: grain.size, imageHeight: imageHeight) * ParticlePerspective.scale(grain.depth))
            let spread = grain.isCloud ? 1 + grain.age * 0.6 : 1
            node.size = CGSize(width: diameter * spread * (grain.isCloud ? 1.6 : 1), height: diameter * spread)
            node.alpha = CGFloat(SandField.opacity(of: grain))
            node.zPosition = ParticlePerspective.layer(grain.depth) + 0.001
        }
    }

    func advanceForReview(seconds: Double) {
        for _ in 0..<Int(seconds * 30) {
            if configuration.mode == .live { nightAmount += (nightTarget - nightAmount) * (1 - exp(-1.4 / 30)) }
            simulation.step(delta: 1.0 / 30, configuration: swimmingConfiguration)
        }
        positionContents()
    }
    func restoreSimulation(_ state: AquariumSimulation) {
        // Snapshot/export state may reuse IDs with different species or depths.
        // Recreate their immutable rendering attributes once when restoring.
        for node in fishNodes.values { node.removeFromParent() }
        for node in fishShadows.values { node.removeFromParent() }
        fishNodes.removeAll(keepingCapacity: true); fishShadows.removeAll(keepingCapacity: true)
        simulation = state
        if let framing { simulation.visibleRegion = framing.visibleRegion }
        apply(configuration)
    }
}

@MainActor final class AquariumSurface: SKView {
    let aquarium: AquariumScene
    private var pauseGeneration = 0
    private var appearanceObservation: NSKeyValueObservation?
    var externallyPaused = false { didSet { updatePause() } }
    init(frame: CGRect, configuration: AquariumConfiguration) {
        aquarium = AquariumScene(size: frame.size, configuration: configuration)
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        ignoresSiblingOrder = true
        allowsTransparency = false
        presentScene(aquarium)
        aquarium.setSystemDark(NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua, immediate: true)
        apply(configuration)
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] app, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.aquarium.setSystemDark(app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
                self.updatePause()
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func apply(_ configuration: AquariumConfiguration) {
        aquarium.apply(configuration)
        let conserve = ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState == .serious
        preferredFramesPerSecond = conserve ? min(15, configuration.quality.fps) : configuration.quality.fps
        updatePause()
    }
    func updatePause() {
        pauseGeneration += 1
        let generation = pauseGeneration
        aquarium.resetClock()
        let shouldPause = externallyPaused || aquarium.configuration.mode == .still
        // Let changed settings paint once, then stop the rendering loop in still mode.
        isPaused = false
        if shouldPause {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
                guard let self, self.pauseGeneration == generation else { return }
                self.isPaused = true
            }
        }
    }
    func pngData() -> Data? {
        guard let texture = texture(from: aquarium, crop: CGRect(origin: .zero, size: aquarium.size)) else { return nil }
        return NSBitmapImageRep(cgImage: texture.cgImage()).representation(using: .png, properties: [:])
    }
}
