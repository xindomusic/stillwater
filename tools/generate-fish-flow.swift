// Offline correspondence data for the existing fish photographs. Never run by the app.
import AppKit
import Vision
import CoreVideo

@main struct GenerateFishFlow {
    static let tile = 128
    static func pose(_ index: Int, species: FishSpecies) -> CGImage {
        let url = Artwork.root.appendingPathComponent("Fish/\(species.rawValue)-turns.png")
        let image = NSImage(contentsOf: url)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let r = Artwork.poseRect(index, species: species)
        let crop = image.cropping(to: CGRect(x: CGFloat(r.x) * CGFloat(image.width),
            y: CGFloat(1 - r.y - r.w) * CGFloat(image.height),
            width: CGFloat(r.z) * CGFloat(image.width), height: CGFloat(r.w) * CGFloat(image.height)))!
        let context = CGContext(data: nil, width: tile, height: tile, bitsPerComponent: 8, bytesPerRow: tile * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.35, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: tile, height: tile))
        context.interpolationQuality = .high
        context.draw(crop, in: CGRect(x: 0, y: 0, width: tile, height: tile))
        return context.makeImage()!
    }

    static func flow(from: CGImage, to: CGImage) throws -> [Float] {
        let request = VNGenerateOpticalFlowRequest(targetedCGImage: to, options: [:])
        request.computationAccuracy = .veryHigh
        request.outputPixelFormat = kCVPixelFormatType_TwoComponent32Float
        try VNImageRequestHandler(cgImage: from, options: [:]).perform([request])
        guard let buffer = request.results?.first?.pixelBuffer else { fatalError("Missing optical flow") }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        precondition(CVPixelBufferGetWidth(buffer) == tile && CVPixelBufferGetHeight(buffer) == tile)
        let pointer = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: Float.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer) / MemoryLayout<Float>.stride
        var vectors = (0..<tile).flatMap { y in Array(UnsafeBufferPointer(start: pointer + y * stride, count: tile * 2)) }
        // Regularize the field to keep thin fins and occluded mouths from folding over.
        for _ in 0..<3 {
            var smooth = vectors
            for y in 0..<tile { for x in 0..<tile { for c in 0..<2 {
                var sum: Float = 0
                for dy in -2...2 { for dx in -2...2 {
                    sum += vectors[(max(0, min(tile - 1, y + dy)) * tile + max(0, min(tile - 1, x + dx))) * 2 + c]
                } }
                smooth[(y * tile + x) * 2 + c] = sum / 25
            } } }
            vectors = smooth
        }
        for p in 0..<(tile * tile) {
            let length = hypot(vectors[p * 2], vectors[p * 2 + 1])
            let limit = Float(tile) * 0.12
            if length > limit { vectors[p * 2] *= limit / length; vectors[p * 2 + 1] *= limit / length }
        }
        return vectors
    }

    static func main() throws {
        let output = CommandLine.arguments.dropFirst().first ?? "Resources/Fish/turn-correspondence.flow"
        // Eight columns (pose pairs), eight rows (forward/backward for each species).
        var bytes = [UInt8](repeating: 0, count: tile * tile * 64 * 4)
        for (speciesIndex, species) in FishSpecies.allCases.enumerated() {
            let poses = (0..<8).map { pose($0, species: species) }
            for i in 0..<8 {
                for reverse in 0..<2 {
                    try autoreleasepool {
                        let vectors = try flow(from: poses[reverse == 0 ? i : (i + 1) % 8],
                                               to: poses[reverse == 0 ? (i + 1) % 8 : i])
                        for y in 0..<tile { for x in 0..<tile {
                            let dst = (((speciesIndex * 2 + reverse) * tile + y) * tile * 8 + i * tile + x) * 4
                            for c in 0..<2 {
                                // Signed normalized displacement, ±0.5, with exact zero at 128.
                                let value = Double(vectors[(y * tile + x) * 2 + c]) / Double(tile)
                                bytes[dst + c] = UInt8(max(0, min(255, (value * 254 + 128).rounded())))
                            }
                            bytes[dst + 2] = 0; bytes[dst + 3] = 255
                        } }
                    }
                }
                print("\(species.rawValue) turn \(i + 1)/8")
                fflush(stdout)
            }
        }
        try Data(bytes).write(to: URL(fileURLWithPath: output))
        print("Wrote \(bytes.count) bytes to \(output)")
    }
}
