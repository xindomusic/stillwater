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
        let bitmap = gpuImageContext.createCGImage(mask, from: CGRect(x: 0, y: 0, width: width, height: height))!
        let texture = SKTexture(cgImage: bitmap)
        texture.filteringMode = .linear
        regionTextures[theme] = texture
        return texture
    }
    /// Core Image filters run on the GPU through Metal; one shared context avoids re-creating pipelines.
    private static let gpuImageContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])

    /// A soft white dot for floating particles, tinted per sprite.
    static let mote: SKTexture = {
        let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillEllipse(in: CGRect(x: 1, y: 1, width: 14, height: 14))
        let texture = SKTexture(cgImage: context.makeImage()!)
        texture.filteringMode = .linear
        return texture
    }()

    private static var sandColors: [String: NSColor] = [:]
    /// The colour of the lit sand at a point on the bed, sampled from the artwork around it.
    static func sandColor(_ theme: AquariumTheme, x: Double, y: Double) -> NSColor {
        let key = "\(theme.rawValue)-\(Int(x * 100))-\(Int(y * 100))"
        if let cached = sandColors[key] { return cached }
        let width = 192, height = 80
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if let source = image(theme).cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        // Memory rows run top-down; y is measured up from the bottom of the artwork.
        let centerRow = min(height - 2, max(1, Int((1 - y) * Double(height))))
        let centerColumn = min(width - 1, max(0, Int(x * Double(width))))
        var samples: [[Double]] = []
        for row in max(0, centerRow - 2)...min(height - 1, centerRow + 2) {
            for column in max(0, centerColumn - 6)...min(width - 1, centerColumn + 6) {
                let i = (row * width + column) * 4
                samples.append((0..<3).map { Double(pixels[i + $0]) / 255 })
            }
        }
        // The median sample: the typical sand here, not a stray pebble or highlight.
        let sorted = samples.sorted { $0.reduce(0, +) < $1.reduce(0, +) }
        let middle = sorted[(sorted.count / 4)..<max(sorted.count / 4 + 1, sorted.count * 3 / 4)]
        let mean = (0..<3).map { c in middle.map { $0[c] }.reduce(0, +) / Double(middle.count) }
        let color = NSColor(srgbRed: mean[0], green: mean[1], blue: mean[2], alpha: 1)
        sandColors[key] = color
        return color
    }

    /// A few irregular sand grains, lit from above, so a puff reads as sand rather than dots.
    static let sandGrains: [SKTexture] = (0..<4).map { variant in
        let size = 24
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var dice = Dice(seed: 0x5A4D + UInt64(variant))
        let corners = 6 + variant % 3
        let stretch = dice.value(0.6...1.0)
        let path = CGMutablePath()
        for k in 0..<corners {
            let angle = Double(k) / Double(corners) * 2 * .pi
            let radius = dice.value(7...11)
            let point = CGPoint(x: 12 + cos(angle) * radius, y: 12 + sin(angle) * radius * stretch)
            if k == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        context.addPath(path); context.clip()
        let colors = [CGColor(gray: 1, alpha: 1), CGColor(gray: 0.86, alpha: 1)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 8, y: 22), end: CGPoint(x: 16, y: 2), options: [])
        let texture = SKTexture(cgImage: context.makeImage()!)
        texture.filteringMode = .linear
        return texture
    }

    /// Which of the crab's eight walking legs each photographed pixel belongs to (red channel:
    /// leg index + 1, times 25; zero for the shell, claws, and water), so the shader can move each
    /// leg as one rigid limb.
    static let crabLegLabels: SKTexture = {
        let side = 512
        let photo = fishTexture(.crab).cgImage()
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(photo, in: CGRect(x: 0, y: 0, width: side, height: side))
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        // Memory rows run top-down; uv y runs up.
        func uv(_ index: Int) -> SIMD2<Double> {
            SIMD2(Double(index % side) + 0.5, Double(side - 1 - index / side) + 0.5) / Double(side)
        }
        func walkable(_ index: Int) -> Bool {
            let p = uv(index), shell = (p - SIMD2(0.5, 0.575)) / SIMD2(0.22, 0.145)
            let claws = abs(p.x - 0.5) < 0.15 && p.y > 0.30 && p.y < 0.49
            return pixels[index * 4 + 3] > 1 && (shell * shell).sum() > 1.0 && !claws
        }
        let legs: [[SIMD2<Double>]] = [[[0.36, 0.63], [0.26, 0.735], [0.17, 0.66]], [[0.33, 0.57], [0.15, 0.63], [0.06, 0.43]],
                                       [[0.33, 0.53], [0.14, 0.50], [0.08, 0.28]], [[0.36, 0.49], [0.23, 0.43], [0.22, 0.20]]]
        func distance(_ p: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
            let edge = b - a, t = max(0, min(1, ((p - a) * edge).sum() / (edge * edge).sum()))
            let d = p - a - edge * t
            return (d * d).sum().squareRoot()
        }
        // Every opaque pixel outside the shell and claws belongs to its nearest leg skeleton.
        var labels = [UInt8](repeating: 0, count: side * side)
        for index in 0..<(side * side) where walkable(index) {
            let p = uv(index)
            var best = 0, bestDistance = 0.16
            for (pair, leg) in legs.enumerated() {
                for mirrored in [false, true] {
                    let q = mirrored ? SIMD2(1 - p.x, p.y) : p
                    let d = min(distance(q, leg[0], leg[1]), distance(q, leg[1], leg[2]))
                    if d < bestDistance { bestDistance = d; best = pair * 2 + (mirrored ? 1 : 0) + 1 }
                }
            }
            labels[index] = UInt8(best)
        }
        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        for i in 0..<(side * side) { rgba[i * 4] = labels[i] * 25; rgba[i * 4 + 3] = 255 }
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return texture
    }()

    /// A soft round glow that fades to transparent, for clouds of stirred-up silt.
    static let softDot: SKTexture = {
        let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0.35), CGColor(gray: 1, alpha: 0)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1])!
        context.drawRadialGradient(gradient, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        let texture = SKTexture(cgImage: context.makeImage()!)
        texture.filteringMode = .linear
        return texture
    }()

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
            // The shrimp is drawn so small that a finer texture only sparkles; its fine speckle
            // is filtered out here rather than shimmering on screen.
            let largest: CGFloat = species == .shrimp ? 320 : 640
            let scale = species.usesProfileAsset ? min(1, largest / max(crop.width, crop.height)) : 1
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
        // A firm core where the body rests on the sand, softening outward.
        let colors = [CGColor(gray: 0, alpha: 0.6), CGColor(gray: 0, alpha: 0.32), CGColor(gray: 0, alpha: 0)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1])!
        context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
        return SKTexture(cgImage: context.makeImage()!)
    }()
}

extension NSColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: alpha)
    }
}
