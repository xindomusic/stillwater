import AppKit
import SpriteKit
import CoreImage

enum Artwork {
    static let root: URL = {
        let bundled = Bundle.main.resourceURL!
        if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("Scenes").path) { return bundled }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
    }()
    static func sceneURL(_ theme: AquariumTheme) -> URL { root.appendingPathComponent("Scenes/\(theme.assetName).png") }
    static func image(_ theme: AquariumTheme) -> NSImage { NSImage(contentsOf: sceneURL(theme)) ?? NSImage(size: NSSize(width: 16, height: 9)) }
    private static var regionTextures: [AquariumTheme: SKTexture] = [:]
    static func motionRegions(_ theme: AquariumTheme) -> SKTexture {
        if let existing = regionTextures[theme] { return existing }
        let source = image(theme).cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let width = 512, height = Int(Double(source.height) / Double(source.width) * 512)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(width * height) {
            let r = Double(bytes[i * 4]) / 255, g = Double(bytes[i * 4 + 1]) / 255, b = Double(bytes[i * 4 + 2]) / 255
            let vegetation = min((g - r * 0.85) / (g + 0.12), (g - b) / (g + 0.12))
            bytes[i * 4] = UInt8(max(0, min(1, (vegetation - 0.035) / 0.16)) * 255)
            bytes[i * 4 + 1] = UInt8(max(0, min(1, (b - r - 0.015) * 15)) * 255)
            bytes[i * 4 + 2] = 0; bytes[i * 4 + 3] = 255
        }
        // Include a soft margin around leaves so their cutout edges move with them.
        let mask = CIImage(cgImage: context.makeImage()!).clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 2])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.5])
        let bitmap = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(mask, from: CGRect(x: 0, y: 0, width: width, height: height))!
        let texture = SKTexture(cgImage: bitmap)
        texture.filteringMode = .linear
        regionTextures[theme] = texture
        return texture
    }
    private static let fishTextures: [FishSpecies: SKTexture] = Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map { species in
        let image = NSImage(contentsOf: root.appendingPathComponent("Fish/\(species.rawValue)-turns.png"))!
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return (species, texture)
    })
    static func fishTexture(_ species: FishSpecies) -> SKTexture { fishTextures[species]! }
    static let turnCorrespondence: SKTexture = {
        let bytes = try! Data(contentsOf: root.appendingPathComponent("Fish/turn-correspondence.flow"))
        precondition(bytes.count == 1024 * 1024 * 4)
        let texture = SKTexture(data: bytes, size: CGSize(width: 1024, height: 1024), flipped: true)
        texture.filteringMode = .linear
        return texture
    }()
    // The generated poses have variable widths. Source rectangles keep each whole fish
    // centered at constant physical scale, including the narrow head-on and tail-on views.
    static func poseRect(_ index: Int, species: FishSpecies) -> SIMD4<Float> {
        let extents: [(Float, Float)]
        switch species {
        case .rasbora: extents = [(25,522),(556,915),(1021,1283),(1354,1702),(24,555),(629,935),(1024,1283),(1382,1717)]
        case .cherry: extents = [(19,567),(614,971),(1060,1322),(1397,1727),(14,566),(614,971),(1063,1311),(1402,1749)]
        case .pearl: extents = [(26,535),(596,881),(1013,1268),(1397,1705),(16,528),(602,904),(1019,1266),(1397,1705)]
        case .loach: extents = [(17,645),(692,1050),(1107,1321),(1386,1708),(19,645),(695,1044),(1129,1297),(1408,1741)]
        }
        let (left, right) = extents[index]
        return SIMD4((left - 6) / 1774, index < 4 ? 0.5 : 0, (right - left + 12) / 1774, 0.5)
    }
    static func fishImage(_ species: FishSpecies) -> NSImage {
        let r = poseRect(0, species: species)
        let cg = SKTexture(rect: CGRect(x: CGFloat(r.x), y: CGFloat(r.y), width: CGFloat(r.z), height: CGFloat(r.w)), in: fishTexture(species)).cgImage()
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
    static let contactShadow: SKTexture = {
        let context = CGContext(data: nil, width: 128, height: 32, bitsPerComponent: 8, bytesPerRow: 512,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 64, y: 16); context.scaleBy(x: 64, y: 16)
        let colors = [CGColor(gray: 0, alpha: 0.24), CGColor(gray: 0, alpha: 0)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
        return SKTexture(cgImage: context.makeImage()!)
    }()
}

extension NSColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: alpha)
    }
}
