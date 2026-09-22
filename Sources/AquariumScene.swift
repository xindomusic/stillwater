import AppKit
import SpriteKit

private final class FishSprite: SKSpriteNode {
    let poseValue = SKAttributeValue(float: 0)
    let phaseValue = SKAttributeValue(float: 0)
    let strokeValue = SKAttributeValue(vectorFloat4: .zero)
    let finsValue = SKAttributeValue(vectorFloat4: .zero)
    let curveValue = SKAttributeValue(vectorFloat4: .zero)
}

final class AquariumScene: SKScene {
    private(set) var configuration: AquariumConfiguration
    private(set) var simulation = AquariumSimulation()
    private(set) var frameCount = 0
    private let backdrop = SKSpriteNode()
    private let shade = SKSpriteNode(color: .black, size: .zero)
    private var fishNodes: [Int: FishSprite] = [:]
    private var foodNodes: [Int: SKSpriteNode] = [:]
    private var fishShadows: [Int: SKSpriteNode] = [:]
    private var framing: AquariumFraming?
    private var motes: [SKShapeNode] = []
    private var bubbleNodes: [SKSpriteNode] = []
    private var previousTime: TimeInterval?
    private(set) var nightAmount = 0.0
    private(set) var systemIsDark = false
    private var nightTarget = 0.0
    private let backgroundShader = SKShader(source: WaterRendering.shaderSource)
    private let fishShader = FishRendering.makeShader()
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
            let dot = SKShapeNode(circleOfRadius: i % 4 == 0 ? 1.1 : 0.65)
            dot.fillColor = NSColor(rgb: 0xe6effa, alpha: 0.18)
            dot.strokeColor = .clear
            dot.zPosition = CGFloat(i % 3) + 15
            addChild(dot); motes.append(dot)
        }
        for i in 0..<14 {
            let bubble = SKSpriteNode()
            bubble.name = "bubble-\(i)"
            bubble.shader = bubbleShader
            bubble.zPosition = 20
            addChild(bubble); bubbleNodes.append(bubble)
        }
        apply(configuration, force: true)
    }
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didChangeSize(_ oldSize: CGSize) { layoutBackdrop(); positionContents() }
    private func layoutBackdrop() {
        guard let texture = backdrop.texture, size.width > 0, size.height > 0 else { return }
        let layout = AquariumFraming(viewport: size, image: texture.size())
        framing = layout
        backdrop.size = layout.imageRect.size
        backdrop.position = CGPoint(x: layout.imageRect.midX, y: layout.imageRect.midY)
        simulation.visibleRegion = layout.visibleRegion
        simulation.synchronize(configuration)
        for fish in simulation.fish {
            let body = fish.species.bodySize * fish.depth * max(0.1, layout.imageRect.height / 900)
            fishNodes[fish.id]?.size = CGSize(width: body, height: body)
            fishShadows[fish.id]?.size = CGSize(width: body * 0.72, height: body * 0.08)
        }
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
            node.setValue(SKAttributeValue(float: Float(fish.depth)), forAttribute: "a_depth")
            node.setValue(SKAttributeValue(float: fish.species.renderingKind), forAttribute: "a_species")
            node.setValue(SKAttributeValue(vectorFloat2: Artwork.fishSampleScale(fish.species)), forAttribute: "a_sampleScale")
            node.setValue(SKAttributeValue(vectorFloat2: Artwork.fishVisibleY(fish.species)), forAttribute: "a_visibleY")
            node.setValue(SKAttributeValue(vectorFloat4: Artwork.fishProfileRect), forAttribute: "a_rect0")
            let body = fish.species.bodySize * fish.depth * max(0.1, (framing?.imageRect.height ?? size.height) / 900)
            node.size = CGSize(width: body, height: body)
            node.zPosition = CGFloat(5 + fish.depth)
            addChild(node); fishNodes[fish.id] = node
            if fish.species.isBottomDweller {
                let shadow = SKSpriteNode(texture: Artwork.contactShadow)
                shadow.zPosition = 4
                shadow.size = CGSize(width: body * 0.72, height: body * 0.08)
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
        let scale = max(0.1, (framing?.imageRect.height ?? size.height) / 900)
        for f in simulation.fish {
            guard let node = fishNodes[f.id] else { continue }
            let body = f.species.bodySize * f.depth * scale
            node.position = framing?.point(x: f.x, y: f.y) ?? CGPoint(x: f.x * size.width, y: f.y * size.height)
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
            node.curveValue.vectorFloat4Value = f.spineCurve; node.setValue(node.curveValue, forAttribute: "a_curve")
            let bite: Double
            if !f.species.isInvertebrate, let response = f.feeding, response.phase == .nibbling {
                let envelope = min(1, response.age * 6) * min(1, max(0, response.remaining) * 6)
                bite = sin(response.age * 18) * 0.045 * envelope
            } else { bite = 0 }
            node.zRotation = CGFloat((f.pitch + bite) * cos(f.yaw))
            // Distance changes color, never the opacity of a fish's body.
            if let shadow = fishShadows[f.id] {
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
            let node: SKSpriteNode
            if let existing = foodNodes[pellet.id] { node = existing }
            else {
                node = SKSpriteNode(color: .white, size: .zero)
                node.name = "pellet-\(pellet.id)"
                node.shader = pelletShader
                addChild(node); foodNodes[pellet.id] = node
            }
            node.position = framing?.point(x: pellet.x, y: pellet.y) ?? .zero
            let diameter = 13 * scale * pellet.size * ParticlePerspective.scale(pellet.depth)
            node.size = CGSize(width: diameter, height: diameter)
            node.zPosition = ParticlePerspective.layer(pellet.depth)
            node.alpha = CGFloat(min(1, (70 - pellet.age) / 4))
            node.setValue(SKAttributeValue(float: Float(pellet.depth)), forAttribute: "a_depth")
            node.setValue(SKAttributeValue(float: Float(pellet.tumble)), forAttribute: "a_tumble")
            node.setValue(SKAttributeValue(float: Float(pellet.rotation)), forAttribute: "a_roll")
            node.setValue(SKAttributeValue(float: Float(pellet.phase)), forAttribute: "a_seed")
            node.setValue(SKAttributeValue(float: Float(min(0.25, 1.0 / max(1, diameter)))), forAttribute: "a_edge")
        }
        for (i, dot) in motes.enumerated() where configuration.particles {
            let n = Double(i)
            let x = (n * 0.6180339 + sin(clock * 0.08 + n) * 0.012).truncatingRemainder(dividingBy: 1)
            let y = (n * 0.381966 + clock * 0.003).truncatingRemainder(dividingBy: 1)
            dot.position = CGPoint(x: (x < 0 ? x + 1 : x) * size.width, y: y * size.height)
            dot.setScale(scale)
        }
        for (i, bubble) in bubbleNodes.enumerated() where configuration.bubbles {
            guard simulation.bubbles.indices.contains(i) else { bubble.alpha = 0; continue }
            let state = simulation.bubbles[i]
            bubble.position = framing?.point(x: state.x, y: state.y) ?? .zero
            let top = simulation.visibleRegion.top
            bubble.alpha = state.age < 0 ? 0 : CGFloat(min(1, state.age * 1.7) * min(1, max(0, top - state.y) * 14))
            let expansion = 1 + max(0, state.y - state.originY) * 0.10
            let diameter = scale * state.radius * 2 * expansion * ParticlePerspective.scale(state.depth)
            bubble.zPosition = ParticlePerspective.layer(state.depth)
            bubble.setValue(SKAttributeValue(float: Float(state.depth)), forAttribute: "a_depth")
            let wobble = sin(max(0, state.age) * 2.6 + state.phase) * 0.025
            bubble.size = CGSize(width: diameter * (1 + wobble), height: diameter / (1 + wobble))
            let imageSize = framing?.imageRect.size ?? size
            let w = Float(bubble.size.width / imageSize.width), h = Float(bubble.size.height / imageSize.height)
            bubble.setValue(SKAttributeValue(vectorFloat4: SIMD4(Float(state.x) - w / 2, Float(state.y) - h / 2, w, h)), forAttribute: "a_waterRect")
            bubble.setValue(SKAttributeValue(float: Float(min(0.5, 1.5 / max(1, diameter)))), forAttribute: "a_edge")
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
