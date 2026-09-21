import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (name, pixels) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let size = CGFloat(pixels)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let inset = size * 0.07
    let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let shape = NSBezierPath(roundedRect: rect, xRadius: size * 0.20, yRadius: size * 0.20)
    let gradient = NSGradient(starting: NSColor(srgbRed: 0.06, green: 0.14, blue: 0.27, alpha: 1), ending: NSColor(srgbRed: 0.20, green: 0.39, blue: 0.71, alpha: 1))!
    gradient.draw(in: shape, angle: 70)
    let fish = NSBezierPath()
    fish.move(to: NSPoint(x: size * 0.73, y: size * 0.51))
    fish.curve(to: NSPoint(x: size * 0.34, y: size * 0.51), controlPoint1: NSPoint(x: size * 0.58, y: size * 0.74), controlPoint2: NSPoint(x: size * 0.43, y: size * 0.70))
    fish.line(to: NSPoint(x: size * 0.20, y: size * 0.66))
    fish.curve(to: NSPoint(x: size * 0.20, y: size * 0.36), controlPoint1: NSPoint(x: size * 0.23, y: size * 0.56), controlPoint2: NSPoint(x: size * 0.23, y: size * 0.46))
    fish.line(to: NSPoint(x: size * 0.34, y: size * 0.51))
    fish.curve(to: NSPoint(x: size * 0.73, y: size * 0.51), controlPoint1: NSPoint(x: size * 0.43, y: size * 0.32), controlPoint2: NSPoint(x: size * 0.58, y: size * 0.30))
    fish.close()
    NSColor(srgbRed: 0.89, green: 0.95, blue: 1.0, alpha: 1).setFill(); fish.fill()
    NSColor(srgbRed: 0.08, green: 0.18, blue: 0.34, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: size * 0.61, y: size * 0.525, width: size * 0.035, height: size * 0.035)).fill()
    let bubble = NSBezierPath(ovalIn: NSRect(x: size * 0.73, y: size * 0.64, width: size * 0.07, height: size * 0.07))
    NSColor(srgbRed: 0.65, green: 0.81, blue: 1.0, alpha: 0.5).setStroke(); bubble.lineWidth = size * 0.009; bubble.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(name).png"))
}
