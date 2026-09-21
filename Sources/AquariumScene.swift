import AppKit
import SpriteKit

final class AquariumScene: SKScene {
    private(set) var configuration: AquariumConfiguration
    private(set) var simulation = AquariumSimulation()
    private(set) var frameCount = 0
    private let backdrop = SKSpriteNode()
    private let shade = SKSpriteNode(color: .black, size: .zero)
    private var fishNodes: [Int: SKSpriteNode] = [:]
    private var foodNodes: [Int: SKShapeNode] = [:]
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
        for _ in 0..<14 {
            let bubble = SKSpriteNode()
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
        shade.size = size
        shade.position = backdrop.position
    }

    func apply(_ next: AquariumConfiguration, force: Bool = false) {
        let changedScene = next.theme != configuration.theme || force
        configuration = next
        resolveLighting(immediate: force)
        if changedScene {
            backdrop.texture = SKTexture(image: Artwork.image(next.theme))
            backgroundShader.uniformNamed("u_regions")?.textureValue = Artwork.motionRegions(next.theme)
            bubbleNodes.forEach { $0.texture = backdrop.texture }
            layoutBackdrop()
        }
        backgroundShader.uniformNamed("u_sway")?.floatValue = Float(next.plantSway)
        backgroundShader.uniformNamed("u_shimmer")?.floatValue = Float(next.shimmer)
        backgroundShader.uniformNamed("u_brightness")?.floatValue = Float(next.brightness)
        fishShader.uniformNamed("u_brightness")?.floatValue = Float(min(1.15, next.brightness) * 0.95)
        bubbleShader.uniformNamed("u_brightness")?.floatValue = Float(next.brightness)
        simulation.synchronize(next)
        let liveIDs = Set(simulation.fish.map(\.id))
        for id in Array(fishNodes.keys) where !liveIDs.contains(id) {
            fishNodes.removeValue(forKey: id)?.removeFromParent()
            fishShadows.removeValue(forKey: id)?.removeFromParent()
        }
        for fish in simulation.fish where fishNodes[fish.id] == nil {
            let node = SKSpriteNode(texture: Artwork.fishTexture(fish.species))
            node.shader = fishShader
            node.setValue(SKAttributeValue(float: Float(fish.depth)), forAttribute: "a_depth")
            node.setValue(SKAttributeValue(float: Float(FishSpecies.allCases.firstIndex(of: fish.species)!)), forAttribute: "a_species")
            let width: Float = fish.species == .loach ? 0.39 : 0.335
            node.setValue(SKAttributeValue(vectorFloat2: SIMD2(width, width * 2)), forAttribute: "a_sampleScale")
            node.zPosition = CGFloat(5 + fish.depth)
            addChild(node); fishNodes[fish.id] = node
            if fish.species == .loach {
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
        backgroundShader.uniformNamed("u_night")?.floatValue = Float(nightAmount)
        fishShader.uniformNamed("u_night")?.floatValue = Float(nightAmount)
        bubbleShader.uniformNamed("u_night")?.floatValue = Float(nightAmount)
        backgroundShader.uniformNamed("u_clock")?.floatValue = Float(clock)
        let scale = max(0.1, (framing?.imageRect.height ?? size.height) / 900)
        for f in simulation.fish {
            guard let node = fishNodes[f.id] else { continue }
            let body = f.species.bodySize * f.depth * scale
            node.size = CGSize(width: body, height: body)
            node.position = framing?.point(x: f.x, y: f.y) ?? CGPoint(x: f.x * size.width, y: f.y * size.height)
            let wrappedYaw = (f.yaw.truncatingRemainder(dividingBy: 2 * .pi) + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
            let pose = wrappedYaw / (.pi / 4)
            node.setValue(SKAttributeValue(float: Float(pose)), forAttribute: "a_pose")
            node.setValue(SKAttributeValue(vectorFloat4: Artwork.poseRect(Int(pose), species: f.species)), forAttribute: "a_rect0")
            node.setValue(SKAttributeValue(vectorFloat4: Artwork.poseRect((Int(pose) + 1) % 8, species: f.species)), forAttribute: "a_rect1")
            node.setValue(SKAttributeValue(float: Float(f.finPhase)), forAttribute: "a_finPhase")
            node.setValue(SKAttributeValue(float: Float(f.activity)), forAttribute: "a_activity")
            let bite: Double
            if let response = f.feeding, response.phase == .nibbling {
                let envelope = min(1, response.age * 6) * min(1, max(0, response.remaining) * 6)
                bite = sin(response.age * 18) * 0.045 * envelope
            } else { bite = 0 }
            node.zRotation = CGFloat((max(-0.27, min(0.27, f.vy * 9)) + bite) * cos(f.yaw))
            // Distance changes color, never the opacity of a fish's body.
            node.alpha = 1
            if let shadow = fishShadows[f.id] {
                shadow.position = CGPoint(x: node.position.x, y: node.position.y - body * 0.085)
                shadow.size = CGSize(width: body * 0.72, height: body * 0.08)
            }
        }
        let pelletIDs = Set(simulation.food.map(\.id))
        for id in Array(foodNodes.keys) where !pelletIDs.contains(id) { foodNodes.removeValue(forKey: id)?.removeFromParent() }
        for pellet in simulation.food {
            let node: SKShapeNode
            if let existing = foodNodes[pellet.id] { node = existing }
            else {
                node = SKShapeNode(ellipseOf: CGSize(width: 5.2, height: 3.1))
                node.fillColor = NSColor(rgb: 0xb28650); node.strokeColor = NSColor(rgb: 0xe5c38f, alpha: 0.5); node.lineWidth = 0.35
                node.zPosition = 8; addChild(node); foodNodes[pellet.id] = node
            }
            node.position = framing?.point(x: pellet.x, y: pellet.y) ?? .zero
            node.setScale(scale * pellet.size)
            node.alpha = CGFloat(min(1, (70 - pellet.age) / 4) * (1 - nightAmount * 0.30))
            node.zRotation = CGFloat(pellet.rotation)
        }
        for (i, dot) in motes.enumerated() {
            let n = Double(i)
            let x = (n * 0.6180339 + sin(clock * 0.08 + n) * 0.012).truncatingRemainder(dividingBy: 1)
            let y = (n * 0.381966 + clock * 0.003).truncatingRemainder(dividingBy: 1)
            dot.position = CGPoint(x: (x < 0 ? x + 1 : x) * size.width, y: y * size.height)
            dot.setScale(scale)
        }
        for (i, bubble) in bubbleNodes.enumerated() {
            guard simulation.bubbles.indices.contains(i) else { bubble.alpha = 0; continue }
            let state = simulation.bubbles[i]
            bubble.position = framing?.point(x: state.x, y: state.y) ?? .zero
            let top = simulation.visibleRegion.top
            bubble.alpha = state.age < 0 ? 0 : CGFloat(min(1, state.age * 1.7) * min(1, max(0, top - state.y) * 14))
            let expansion = 1 + max(0, state.y - state.originY) * 0.10
            let diameter = scale * state.radius * 2 * expansion
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
