import AppKit
import SpriteKit
import ImageIO
import UniformTypeIdentifiers

@main struct RenderingTests {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fatalError(message) }
    }
    static func pixels(_ image: CGImage) -> [UInt8] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/rendering-review")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 360), styleMask: [.titled], backing: .buffered, defer: false)
        let view = SKView(frame: window.contentView!.bounds)
        window.contentView = view; window.orderFront(nil)
        let scene = SKScene(size: CGSize(width: 1600, height: 880))
        scene.scaleMode = .aspectFit; scene.backgroundColor = NSColor(rgb: 0x344958)
        view.presentScene(scene); view.isPaused = true
        let legacy = CommandLine.arguments.count > 2 ? try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8) : nil
        for (name, source) in [("current", nil as String?), ("legacy", legacy)] {
            if name == "legacy" && source == nil { continue }
            scene.removeAllChildren()
            let shader = FishRendering.makeShader(source: source)
            for (row, species) in FishSpecies.allCases.enumerated() {
                for column in 0..<8 {
                    let pose = Float(column) + 0.5
                    let node = SKSpriteNode(texture: Artwork.fishTexture(species))
                    node.shader = shader; node.size = CGSize(width: 240, height: 240)
                    node.position = CGPoint(x: 100 + column * 200, y: 755 - row * 215)
                    node.setValue(SKAttributeValue(float: 1), forAttribute: "a_depth")
                    node.setValue(SKAttributeValue(float: 0.9), forAttribute: "a_finPhase")
                    node.setValue(SKAttributeValue(vectorFloat4: SIMD4(0.48,0.12,0,0)), forAttribute: "a_stroke")
                    node.setValue(SKAttributeValue(vectorFloat4: SIMD4(0.7,1.2,0.5,0.65)), forAttribute: "a_fins")
                    node.setValue(SKAttributeValue(vectorFloat4: SIMD4(-0.23,0.10,-0.035,0)), forAttribute: "a_curve")
                    node.setValue(SKAttributeValue(float: 0.3), forAttribute: "a_activity")
                    node.setValue(SKAttributeValue(float: pose), forAttribute: "a_pose")
                    node.setValue(SKAttributeValue(float: Float(row)), forAttribute: "a_species")
                    node.setValue(SKAttributeValue(vectorFloat4: Artwork.fishProfileRect), forAttribute: "a_rect0")
                    node.setValue(SKAttributeValue(vectorFloat4: Artwork.poseRect((column + 1) % 8, species: species)), forAttribute: "a_rect1")
                    node.setValue(SKAttributeValue(vectorFloat2: Artwork.fishSampleScale(species)), forAttribute: "a_sampleScale")
                    node.setValue(SKAttributeValue(vectorFloat2: Artwork.fishVisibleY(species)), forAttribute: "a_visibleY")
                    scene.addChild(node)
                    let label = SKLabelNode(text: "\(species.rawValue) · \(Int(pose * 45))°")
                    label.fontName = "Helvetica"; label.fontSize = 13
                    label.position = CGPoint(x: node.position.x, y: node.position.y - 99)
                    scene.addChild(label)
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            guard let texture = view.texture(from: scene, crop: CGRect(origin: .zero, size: scene.size)) else { fatalError("Renderer unavailable") }
            let image = texture.cgImage()
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try png.write(to: output.appendingPathComponent("turns-\(name).png"))
        }
        // A red view turning into a blue view must never render a purple double exposure.
        scene.removeAllChildren(); scene.size = CGSize(width: 128, height: 128)
        var pixels = [UInt8](repeating: 255, count: 256 * 128 * 4)
        for y in 0..<128 { for x in 0..<256 {
            let p = (y * 256 + x) * 4
            pixels[p] = x < 128 ? 255 : 0; pixels[p + 1] = 0; pixels[p + 2] = x < 128 ? 0 : 255
        } }
        let fixture = SKSpriteNode(texture: SKTexture(data: Data(pixels), size: CGSize(width: 256, height: 128)))
        fixture.shader = FishRendering.makeShader(); fixture.size = scene.size; fixture.position = CGPoint(x: 64, y: 64)
        fixture.setValue(SKAttributeValue(float: 1.15), forAttribute: "a_depth")
        fixture.setValue(SKAttributeValue(float: 0), forAttribute: "a_finPhase")
        fixture.setValue(SKAttributeValue(float: 0), forAttribute: "a_activity")
        fixture.setValue(SKAttributeValue(float: 0), forAttribute: "a_species")
        fixture.setValue(SKAttributeValue(vectorFloat4: SIMD4(0, 0, 0.5, 1)), forAttribute: "a_rect0")
        fixture.setValue(SKAttributeValue(vectorFloat4: SIMD4(0.5, 0, 0.5, 1)), forAttribute: "a_rect1")
        fixture.setValue(SKAttributeValue(vectorFloat2: SIMD2(0.335, 0.67)), forAttribute: "a_sampleScale")
        scene.addChild(fixture)
        for turn in [Float(0.25), 0.49, 0.5, 0.51, 0.75] {
            fixture.setValue(SKAttributeValue(float: turn), forAttribute: "a_pose")
            let bitmap = NSBitmapImageRep(cgImage: view.texture(from: scene)!.cgImage())
            let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
            require(max(color.redComponent, color.blueComponent) > min(color.redComponent, color.blueComponent) * 4,
                    "Turning fish mixed unrelated source colors into a double exposure")
        }
        print("PASS: native turn shader has one visible source at every tested transition")

        scene.removeAllChildren(); scene.size = CGSize(width: 256, height: 256); scene.backgroundColor = .clear
        var largestTurnChange = 0.0
        for (speciesIndex, species) in FishSpecies.allCases.enumerated() {
            let node = SKSpriteNode(texture: Artwork.fishTexture(species))
            node.shader = FishRendering.makeShader(); node.size = CGSize(width: 240, height: 240); node.position = CGPoint(x: 128, y: 128)
            node.setValue(SKAttributeValue(float: 1), forAttribute: "a_depth")
            node.setValue(SKAttributeValue(float: 0.9), forAttribute: "a_finPhase")
            node.setValue(SKAttributeValue(vectorFloat4: SIMD4(0.48,0.12,0,0)), forAttribute: "a_stroke")
            node.setValue(SKAttributeValue(vectorFloat4: SIMD4(0.7,1.2,0.5,0.65)), forAttribute: "a_fins")
            node.setValue(SKAttributeValue(vectorFloat4: SIMD4(-0.23,0.10,-0.035,0)), forAttribute: "a_curve")
            node.setValue(SKAttributeValue(float: 0.3), forAttribute: "a_activity")
            node.setValue(SKAttributeValue(float: Float(speciesIndex)), forAttribute: "a_species")
            node.setValue(SKAttributeValue(vectorFloat4: Artwork.fishProfileRect), forAttribute: "a_rect0")
            node.setValue(SKAttributeValue(vectorFloat2: Artwork.fishSampleScale(species)), forAttribute: "a_sampleScale")
            node.setValue(SKAttributeValue(vectorFloat2: Artwork.fishVisibleY(species)), forAttribute: "a_visibleY")
            scene.addChild(node)
            for boundary in (0...16).map({ Float($0) / 2 }) {
                var captures: [[UInt8]] = []
                for offset: Float in [-0.002, 0.002] {
                    node.setValue(SKAttributeValue(float: boundary + offset), forAttribute: "a_pose")
                    captures.append(Self.pixels(view.texture(from: scene, crop: CGRect(origin: .zero, size: scene.size))!.cgImage()))
                }
                var difference = 0.0, visible = 0.0
                for p in stride(from: 0, to: captures[0].count, by: 4) {
                    visible += Double(max(captures[0][p + 3], captures[1][p + 3])) * 4
                    for c in 0..<4 { difference += Double(abs(Int(captures[0][p + c]) - Int(captures[1][p + c]))) }
                }
                let change = difference / max(1, visible)
                largestTurnChange = max(largestTurnChange, change)
                require(change < 0.08, "Visible turn jump for \(species) at \(boundary * 45) degrees: \(change)")
            }
            node.removeFromParent()
        }
        require(largestTurnChange > 0.001, "Turn shader must actually rotate; a fallback texture can falsely pass continuity checks")
        print("PASS: continuous turns across all former pose boundaries; largest image change \(largestTurnChange)")

        // Isolate motion on stationary fish so whole-sprite travel cannot hide frozen fins.
        scene.removeAllChildren(); scene.size = CGSize(width: 256, height: 256)
        for (index, species) in FishSpecies.allCases.enumerated() {
            let node = SKSpriteNode(texture: Artwork.fishTexture(species)); node.shader = FishRendering.makeShader()
            node.size = CGSize(width: 240, height: 240); node.position = CGPoint(x: 128, y: 128)
            node.setValue(SKAttributeValue(float: 1), forAttribute: "a_depth")
            node.setValue(SKAttributeValue(float: Float(index)), forAttribute: "a_species")
            node.setValue(SKAttributeValue(vectorFloat4: Artwork.fishProfileRect), forAttribute: "a_rect0")
            node.setValue(SKAttributeValue(vectorFloat2: Artwork.fishSampleScale(species)), forAttribute: "a_sampleScale")
            node.setValue(SKAttributeValue(vectorFloat2: Artwork.fishVisibleY(species)), forAttribute: "a_visibleY")
            scene.addChild(node)
            let still = Self.pixels(view.texture(from: scene, crop: CGRect(origin: .zero, size: scene.size))!.cgImage())
            for finsOnly in [false, true] {
                node.setValue(SKAttributeValue(float: finsOnly ? 0 : 2.2), forAttribute: "a_finPhase")
                node.setValue(SKAttributeValue(vectorFloat4: SIMD4(finsOnly ? 0 : 0.8,0,0,0)), forAttribute: "a_stroke")
                node.setValue(SKAttributeValue(vectorFloat4: finsOnly ? SIMD4(1.7,2.4,0.5,1) : SIMD4(0,0,0.5,0)), forAttribute: "a_fins")
                let moved = Self.pixels(view.texture(from: scene, crop: CGRect(origin: .zero, size: scene.size))!.cgImage())
                var changes = 0, faceChanges = 0
                for y in 0..<256 { for x in 0..<256 {
                    let p = (y * 256 + x) * 4
                    let difference = (0..<4).reduce(0) { $0 + abs(Int(still[p + $1]) - Int(moved[p + $1])) }
                    if difference > 8 { changes += 1; if x > 212 { faceChanges += 1 } }
                } }
                require(changes > 30, "\(species) must visibly move \(finsOnly ? "balancing fins" : "tail") independently")
                require(faceChanges < 8, "\(species) fin motion must keep the face anchored")
            }
            node.removeFromParent()
        }
        print("PASS: all species move tail and balancing fins independently while their faces stay anchored")

        scene.removeAllChildren(); scene.size = CGSize(width: 1000, height: 740); scene.backgroundColor = NSColor(rgb: 0x344958)
        var motorNodes: [SKSpriteNode] = [], motors: [FishStroke] = [], phases: [Double] = []
        for (row, species) in FishSpecies.allCases.enumerated() {
            for column in 0..<3 {
                let node = SKSpriteNode(texture: Artwork.fishTexture(species)); node.shader = FishRendering.makeShader()
                node.position = CGPoint(x: 165 + column * 335, y: 650 - row * 180); node.size = CGSize(width: 265, height: 265)
                node.setValue(SKAttributeValue(float: 1), forAttribute: "a_depth")
                node.setValue(SKAttributeValue(float: Float(row)), forAttribute: "a_species")
                node.setValue(SKAttributeValue(vectorFloat4: Artwork.fishProfileRect), forAttribute: "a_rect0")
                node.setValue(SKAttributeValue(vectorFloat2: Artwork.fishSampleScale(species)), forAttribute: "a_sampleScale")
                node.setValue(SKAttributeValue(vectorFloat2: Artwork.fishVisibleY(species)), forAttribute: "a_visibleY")
                scene.addChild(node); motorNodes.append(node); motors.append(FishStroke(seed: UInt64(row * 17 + column + 31))); phases.append(Double(row + column))
                let label = SKLabelNode(text: "\(species.rawValue) · \(["hover", "cruise & turn", "dash"][column])")
                label.fontName = "Helvetica"; label.fontSize = 14; label.position = CGPoint(x: node.position.x, y: node.position.y - 77); scene.addChild(label)
            }
        }
        let gif = CGImageDestinationCreateWithURL(output.appendingPathComponent("fin-motion.gif") as CFURL, UTType.gif.identifier as CFString, 120, nil)!
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<120 {
            autoreleasepool {
                for i in motorNodes.indices {
                    let turning = i % 3 == 1
                    let turnClock = Double(frame) / 20 * 0.9
                    let yaw = turning ? Double.pi * (0.5 - 0.5 * cos(turnClock)) : 0
                    let turnRate = turning ? Double.pi * 0.45 * sin(turnClock) : 0
                    motors[i].advance(delta: 1.0 / 20, species: FishSpecies.allCases[i / 3], speed: [0.035,0.85,2.5][i % 3], acceleration: 0, turnRate: turnRate)
                    motorNodes[i].setValue(SKAttributeValue(float: Float(yaw / (.pi / 4))), forAttribute: "a_pose")
                    phases[i] += motors[i].tailRate / 20
                    motorNodes[i].setValue(SKAttributeValue(float: Float(phases[i])), forAttribute: "a_finPhase")
                    motorNodes[i].setValue(SKAttributeValue(vectorFloat4: SIMD4(Float(motors[i].amplitude),0,0,0)), forAttribute: "a_stroke")
                    motorNodes[i].setValue(SKAttributeValue(vectorFloat4: SIMD4(Float(motors[i].pectoralPhase),Float(motors[i].dorsalPhase),Float(motors[i].spread),Float(motors[i].finAmplitude))), forAttribute: "a_fins")
                    motorNodes[i].setValue(SKAttributeValue(vectorFloat4: motors[i].spineCurve(phase: phases[i], species: FishSpecies.allCases[i / 3])), forAttribute: "a_curve")
                }
                let rendered = view.texture(from: scene, crop: CGRect(origin: .zero, size: scene.size))!.cgImage()
                if frame == 40 {
                    let bytes = Self.pixels(rendered)
                    var strayPixels = 0
                    // Regression: a grazing gourami turn used to draw detached fin
                    // copies in this empty band between the middle and right columns.
                    for y in 0..<rendered.height { for x in 606..<655 {
                        let p = (y * rendered.width + x) * 4
                        if (0..<3).contains(where: { abs(Int(bytes[p + $0]) - Int(bytes[$0])) > 5 }) { strayPixels += 1 }
                    } }
                    require(strayPixels == 0, "Curved turns must not project detached fin copies")
                }
                CGImageDestinationAddImage(gif, rendered, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.05]] as CFDictionary)
                if [20,40,60,100].contains(frame) { try! NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("fin-motion-\(frame).png")) }
            }
        }
        require(CGImageDestinationFinalize(gif), "Motion capture must finish")

        for theme in AquariumTheme.allCases {
            var config = AquariumConfiguration(); config.theme = theme; config.lighting = .day
            config.counts = Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map { ($0.rawValue, 0) })
            config.bubbles = false; config.particles = false; config.plantSway = 0; config.shimmer = 0
            let surface = AquariumSurface(frame: CGRect(x: 0, y: 0, width: 1280, height: 720), configuration: config)
            surface.isPaused = true
            let staticBefore = surface.pngData()!
            surface.aquarium.advanceForReview(seconds: 2)
            require(surface.pngData()! == staticBefore, "Zero water and plant motion must stay static")
            config.plantSway = 0.55; surface.apply(config); surface.isPaused = true
            let plantBefore = surface.pngData()!
            surface.aquarium.advanceForReview(seconds: 2)
            let plantAfter = surface.pngData()!
            require(plantBefore != plantAfter, "Plant sway must be visible for \(theme)")
            try plantBefore.write(to: output.appendingPathComponent("\(theme.rawValue)-plants-before.png"))
            try plantAfter.write(to: output.appendingPathComponent("\(theme.rawValue)-plants-after.png"))
            config.plantSway = 0; config.shimmer = 0.2; surface.apply(config); surface.isPaused = true
            let waterBefore = surface.pngData()!
            surface.aquarium.advanceForReview(seconds: 2)
            require(surface.pngData()! != waterBefore, "Water must move for \(theme)")
            config.plantSway = 0.55; config.bubbles = true; config.mode = .still
            surface.apply(config); surface.isPaused = true
            let stillBefore = surface.pngData()!
            surface.aquarium.advanceForReview(seconds: 2)
            require(surface.pngData()! == stillBefore, "Still mode must freeze all atmospheric shaders")
        }
        print("PASS: all three scenes animate plants and water independently, honor zero settings, and freeze in Still")

        scene.removeAllChildren(); scene.size = CGSize(width: 1000, height: 500)
        let background = SKSpriteNode(texture: SKTexture(image: Artwork.image(.river)))
        background.size = scene.size; background.position = CGPoint(x: 500, y: 250); scene.addChild(background)
        let bubbleShader = BubbleRendering.makeShader()
        for (i, diameter) in [CGFloat(12), 18, 28, 44, 76, 110].enumerated() {
            let bubble = SKSpriteNode(texture: background.texture)
            bubble.shader = bubbleShader; bubble.size = CGSize(width: diameter, height: diameter)
            bubble.position = CGPoint(x: 110 + i * 150, y: 250); bubble.zPosition = 1
            let w = Float(diameter / 1000), h = Float(diameter / 500)
            bubble.setValue(SKAttributeValue(vectorFloat4: SIMD4(Float(bubble.position.x / 1000) - w / 2, 0.5 - h / 2, w, h)), forAttribute: "a_waterRect")
            bubble.setValue(SKAttributeValue(float: Float(1.5 / diameter)), forAttribute: "a_edge")
            bubble.setValue(SKAttributeValue(float: 1), forAttribute: "a_depth")
            scene.addChild(bubble)
        }
        try NSBitmapImageRep(cgImage: view.texture(from: scene)!.cgImage()).representation(using: .png, properties: [:])!
            .write(to: output.appendingPathComponent("bubble-material.png"))

        scene.removeAllChildren(); scene.backgroundColor = NSColor(rgb: 0x344958)
        let pelletShader = PelletRendering.makeShader()
        for (column, depth) in [0.62, 0.95, 1.32].enumerated() {
            let x = 170 + column * 330
            let label = SKLabelNode(text: ["FAR", "MIDDLE", "NEAR"][column]); label.fontSize = 16
            label.position = CGPoint(x: x, y: 455); scene.addChild(label)
            let bubble = SKSpriteNode(texture: background.texture); bubble.shader = bubbleShader
            let diameter = 44 * ParticlePerspective.scale(depth)
            bubble.position = CGPoint(x: x, y: 385); bubble.size = CGSize(width: diameter, height: diameter)
            bubble.setValue(SKAttributeValue(float: Float(depth)), forAttribute: "a_depth")
            bubble.setValue(SKAttributeValue(float: Float(1.5 / diameter)), forAttribute: "a_edge")
            bubble.setValue(SKAttributeValue(vectorFloat4: SIMD4(0.48,0.5,0.04,0.08)), forAttribute: "a_waterRect")
            scene.addChild(bubble)
            for row in 0..<3 {
                let node = SKSpriteNode(color: .white, size: .zero); node.shader = pelletShader
                node.position = CGPoint(x: x, y: 285 - row * 95)
                let size = 90 * ParticlePerspective.scale(depth)
                node.size = CGSize(width: size, height: size)
                for (key, value) in [("a_depth", depth), ("a_tumble", Double(row) * 0.7 + 0.3), ("a_roll", Double(row) * 0.6), ("a_seed", 0.4), ("a_edge", 1.0 / size)] {
                    node.setValue(SKAttributeValue(float: Float(value)), forAttribute: key)
                }
                scene.addChild(node)
            }
        }
        try NSBitmapImageRep(cgImage: view.texture(from: scene, crop: CGRect(origin: .zero, size: scene.size))!.cgImage()).representation(using: .png, properties: [:])!
            .write(to: output.appendingPathComponent("particle-depth-materials.png"))

        var feeding = AquariumConfiguration(); feeding.bubbles = true; feeding.lighting = .day
        let feedingSurface = AquariumSurface(frame: CGRect(x: 0, y: 0, width: 1280, height: 720), configuration: feeding)
        feedingSurface.aquarium.feed(); feedingSurface.aquarium.advanceForReview(seconds: 1.3); feedingSurface.isPaused = true
        let fishDepths = feedingSurface.aquarium.simulation.fish.map { 5 + $0.depth }
        for pellet in feedingSurface.aquarium.simulation.food {
            let node = feedingSurface.aquarium.childNode(withName: "pellet-\(pellet.id)")!
            if pellet.depth < 0.7 { require(node.zPosition < fishDepths.min()!, "Far food must pass behind fish") }
            if pellet.depth > 1.2 { require(node.zPosition > fishDepths.max()!, "Near food must pass in front of fish") }
        }
        for (i, bubble) in feedingSurface.aquarium.simulation.bubbles.enumerated() {
            let node = feedingSurface.aquarium.childNode(withName: "bubble-\(i)")!
            if bubble.depth < 0.7 { require(node.zPosition < fishDepths.min()!, "Far bubbles must pass behind fish") }
            if bubble.depth > 1.2 { require(node.zPosition > fishDepths.max()!, "Near bubbles must pass in front of fish") }
        }
        try feedingSurface.pngData()!.write(to: output.appendingPathComponent("feeding-depth.png"))
        feeding.mode = .still; feedingSurface.apply(feeding); feedingSurface.isPaused = true
        let frozenFood = feedingSurface.pngData()!
        feedingSurface.aquarium.advanceForReview(seconds: 3)
        require(feedingSurface.pngData()! == frozenFood, "Still must freeze pellet tumble and all depth effects")
        print("PASS: near/far particle occlusion matches fish depth, with complete Still freeze")
        var restored = AquariumSimulation(seed: 991); restored.synchronize(feeding)
        feedingSurface.aquarium.restoreSimulation(restored)
        for fish in restored.fish {
            let node = feedingSurface.aquarium.childNode(withName: "fish-\(fish.id)") as! SKSpriteNode
            require(abs(node.zPosition - (5 + fish.depth)) < 0.000001 && node.texture?.size() == Artwork.fishTexture(fish.species).size(), "Restored snapshots must refresh cached depth and species")
        }
        print("PASS: snapshot restoration refreshes immutable fish rendering attributes")
        window.orderOut(nil)
        print("Rendered turn comparisons to \(output.path)")
    }
}
