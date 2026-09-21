import AppKit
import SpriteKit
import Darwin

// A controlled renderer probe, intentionally separate from the screenshot-heavy release review.
@main struct PerformanceProbe {
    static func cpu() -> Double {
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
    static func wait(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { autoreleasepool { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) } }
    }
    @MainActor static func main() throws {
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        var config = AquariumConfiguration(); config.lighting = .day
        let desktop = AquariumSurface(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), configuration: config)
        let preview = AquariumSurface(frame: CGRect(x: 0, y: 0, width: 960, height: 540), configuration: config)
        let windows = [desktop, preview].enumerated().map { i, surface -> NSWindow in
            let window = NSWindow(contentRect: surface.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = surface; window.setFrameOrigin(CGPoint(x: i * 120, y: i * 120)); window.orderFront(nil)
            return window
        }
        var samples: [[String: Any]] = []
        for (label, count, quality) in [("default-30", 26, RenderQuality.balanced), ("maximum-30", 120, .balanced), ("maximum-60", 120, .smooth)] {
            for species in FishSpecies.allCases { config.setCount(species, count == 120 ? 30 : species.defaultCount) }
            config.quality = quality
            desktop.apply(config); preview.apply(config)
            wait(3)
            let start = ProcessInfo.processInfo.systemUptime, cpuStart = cpu(), frames = preview.aquarium.frameCount
            wait(6)
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            samples.append(["scenario": label, "fps": Double(preview.aquarium.frameCount - frames) / elapsed,
                "cpuPercentOfOneCore": (cpu() - cpuStart) / elapsed * 100, "physicalFootprintMiB": Double(footprint()) / 1_048_576])
        }
        config.mode = .still; desktop.apply(config); preview.apply(config); wait(0.3)
        let start = cpu(), frames = preview.aquarium.frameCount; wait(2)
        let textureBytes = FishSpecies.allCases.reduce(0.0) { total, species in
            let size = Artwork.fishTexture(species).size(); return total + size.width * size.height * 4
        }
        let result: [String: Any] = ["samples": samples, "stillCPUPercentOfOneCore": (cpu() - start) / 2 * 100,
            "stillFrames": preview.aquarium.frameCount - frames, "fishTextureRGBABytes": textureBytes,
            "scope": "Two visible production surfaces, 1920x1080 and 960x540; six-second samples after three-second warmup. No screenshots, feeding, or global preferences. Not a sustained power benchmark."]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        let output = CommandLine.arguments.dropFirst().first ?? "build/performance.json"
        try data.write(to: URL(fileURLWithPath: output))
        print(String(decoding: data, as: UTF8.self))
        windows.forEach { $0.orderOut(nil) }
    }
}
