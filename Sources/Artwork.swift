import AppKit
import SpriteKit
import CoreImage
import ImageIO

enum Artwork {
    static let root: URL = {
        let bundled = Bundle.main.resourceURL!
        if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("Scenes").path) { return bundled }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
    }()
    static func sceneURL(_ theme: AquariumTheme) -> URL { root.appendingPathComponent("Scenes/\(theme.assetName).png") }
    static func image(_ theme: AquariumTheme) -> NSImage { NSImage(contentsOf: sceneURL(theme)) ?? NSImage(size: NSSize(width: 16, height: 9)) }
    private static var regionTextures: [AquariumTheme: SKTexture] = [:]
    private static var currentSceneTexture: (AquariumTheme, SKTexture)?
    static func sceneTexture(_ theme: AquariumTheme) -> SKTexture {
        if let cached = currentSceneTexture, cached.0 == theme { return cached.1 }
        let texture = SKTexture(image: image(theme))
        currentSceneTexture = (theme, texture)
        return texture
    }
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
    private static var fishTextures: [FishSpecies: SKTexture] = [:]
    private static var fishYBounds: [FishSpecies: SIMD2<Float>] = [:]
    static func fishVisibleY(_ species: FishSpecies) -> SIMD2<Float> {
        _ = fishTexture(species)
        return fishYBounds[species]!
    }
    static let fishProfileRect = SIMD4<Float>(0, 0, 1, 1)
    static func fishSampleScale(_ species: FishSpecies) -> SIMD2<Float> {
        if species.usesProfileAsset { return SIMD2(1.08, 1.08) }
        let rect = poseRect(0, species: species)
        let width: Float = species == .loach ? 0.39 : 0.335
        return SIMD2(width / rect.z, width * 2 / rect.w)
    }
    static func fishTexture(_ species: FishSpecies) -> SKTexture {
        if let cached = fishTextures[species] { return cached }
        // Copy just the profile into a compact backing store. A CGImage crop alone
        // can keep the entire eight-view atlas alive, including seven unused views.
        let profile: CGImage = autoreleasepool {
            let suffix = species.usesProfileAsset ? "profile" : "turns"
            let url = root.appendingPathComponent("Fish/\(species.rawValue)-\(suffix).png")
            let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)!
            let full = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            let rect = poseRect(0, species: species)
            let crop = species.usesProfileAsset ? CGRect(x: 0, y: 0, width: full.width, height: full.height) : CGRect(x: CGFloat(rect.x) * CGFloat(full.width), y: 0,
                width: CGFloat(rect.z) * CGFloat(full.width), height: CGFloat(full.height) / 2).integral
            let scale = species.usesProfileAsset ? min(1, 640 / max(crop.width, crop.height)) : 1
            let context = CGContext(data: nil, width: Int(crop.width * scale), height: Int(crop.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.interpolationQuality = .high
            context.draw(full.cropping(to: crop)!, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
            let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
            var first = context.height, last = 0
            for y in 0..<context.height {
                for x in 0..<context.width where pixels[y * context.bytesPerRow + x * 4 + 3] > 0 {
                    first = min(first, y); last = max(last, y); break
                }
            }
            // CGImage rows run top-down; SpriteKit profile coordinates run bottom-up.
            // Leave room for the fin deformation outside the original silhouette.
            fishYBounds[species] = SIMD2(max(0, 1 - Float(last + 1) / Float(context.height) - 0.045),
                min(1, 1 - Float(first) / Float(context.height) + 0.045))
            return context.makeImage()!
        }
        let texture = SKTexture(cgImage: profile)
        texture.filteringMode = .linear
        fishTextures[species] = texture
        return texture
    }
    // The generated poses have variable widths. Source rectangles keep each whole fish
    // centered at constant physical scale, including the narrow head-on and tail-on views.
    static func poseRect(_ index: Int, species: FishSpecies) -> SIMD4<Float> {
        let extents: [(Float, Float)]
        switch species {
        case .rasbora: extents = [(25,522),(556,915),(1021,1283),(1354,1702),(24,555),(629,935),(1024,1283),(1382,1717)]
        case .cherry: extents = [(19,567),(614,971),(1060,1322),(1397,1727),(14,566),(614,971),(1063,1311),(1402,1749)]
        case .pearl: extents = [(26,535),(596,881),(1013,1268),(1397,1705),(16,528),(602,904),(1019,1266),(1397,1705)]
        case .loach: extents = [(17,645),(692,1050),(1107,1321),(1386,1708),(19,645),(695,1044),(1129,1297),(1408,1741)]
        default: return SIMD4(0, 0, 1, 1)
        }
        let (left, right) = extents[index]
        return SIMD4((left - 6) / 1774, index < 4 ? 0.5 : 0, (right - left + 12) / 1774, 0.5)
    }
    static func fishImage(_ species: FishSpecies) -> NSImage {
        let cg = fishTexture(species).cgImage()
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
