import AppKit
import SpriteKit
import ImageIO
import UniformTypeIdentifiers

@main struct RenderingTests {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fatalError(message) }
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
                    node.setValue(SKAttributeValue(float: 0.3), forAttribute: "a_activity")
                    node.setValue(SKAttributeValue(float: pose), forAttribute: "a_pose")
                    node.setValue(SKAttributeValue(float: Float(row)), forAttribute: "a_species")
                    node.setValue(SKAttributeValue(vectorFloat4: Artwork.poseRect(column, species: species)), forAttribute: "a_rect0")
                    node.setValue(SKAttributeValue(vectorFloat4: Artwork.poseRect((column + 1) % 8, species: species)), forAttribute: "a_rect1")
                    let width: Float = species == .loach ? 0.39 : 0.335
                    node.setValue(SKAttributeValue(vectorFloat2: SIMD2(width, width * 2)), forAttribute: "a_sampleScale")
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
            scene.addChild(bubble)
        }
        try NSBitmapImageRep(cgImage: view.texture(from: scene)!.cgImage()).representation(using: .png, properties: [:])!
            .write(to: output.appendingPathComponent("bubble-material.png"))
        window.orderOut(nil)
        print("Rendered turn comparisons to \(output.path)")
    }
}
