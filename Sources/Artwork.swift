import AppKit
import SpriteKit

enum Artwork {
    static let root: URL = {
        let bundled = Bundle.main.resourceURL!
        if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("Scenes").path) { return bundled }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
    }()
    static func sceneURL(_ theme: AquariumTheme) -> URL { root.appendingPathComponent("Scenes/\(theme.assetName).png") }
    static func image(_ theme: AquariumTheme) -> NSImage { NSImage(contentsOf: sceneURL(theme)) ?? NSImage(size: NSSize(width: 16, height: 9)) }
    private static let fishTextures: [FishSpecies: SKTexture] = Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map { species in
        let image = NSImage(contentsOf: root.appendingPathComponent("Fish/\(species.rawValue)-turns.png"))!
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return (species, texture)
    })
    static func fishTexture(_ species: FishSpecies) -> SKTexture { fishTextures[species]! }
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
