import AppKit

@main struct StillwaterMain {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        let review: URL?
        if let index = arguments.firstIndex(of: "--review"), arguments.indices.contains(index + 1) { review = URL(fileURLWithPath: arguments[index + 1]) }
        else { review = nil }
        if arguments.contains("--replace"), review == nil {
            let current = ProcessInfo.processInfo.processIdentifier
            let previous = NSRunningApplication.runningApplications(withBundleIdentifier: "com.stillwater.aquarium").filter { $0.processIdentifier != current }
            previous.forEach { $0.terminate() }
            let deadline = Date().addingTimeInterval(3)
            while previous.contains(where: { !$0.isTerminated }) && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AquariumApplicationDelegate(reviewDirectory: review)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
