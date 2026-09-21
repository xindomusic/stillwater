import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers
import Darwin
import ImageIO

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AquariumApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let reviewDirectory: URL?
    let store: AquariumStore
    private var settingsWindow: NSWindow?
    private var previewWindow: NSWindow?
    private var desktopWindows: [DesktopWindow] = []
    private var statusItem: NSStatusItem?
    private let feedingShortcut = FeedingShortcut()
    private var subscriptions: Set<AnyCancellable> = []
    private var pauseReasons: Set<String> = []
    private var lastDisplayMode: Bool?
    private var lastWallpaperEnabled: Bool?

    init(reviewDirectory: URL? = nil) {
        self.reviewDirectory = reviewDirectory
        self.store = AquariumStore(persist: reviewDirectory == nil)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        createMainMenu()
        if let reviewDirectory {
            runReview(at: reviewDirectory)
            return
        }
        createStatusItem()
        subscribeToSystem()
        store.feedRequests.sink { [weak self] in self?.allSurfaces().forEach { $0.aquarium.feed() } }.store(in: &subscriptions)
        store.$configuration.sink { [weak self] next in self?.apply(next) }.store(in: &subscriptions)
        showSettings()
        print("Stillwater ready · global feeding shortcut: \(store.feedingShortcutAvailable ? FeedingShortcut.label : "unavailable or disabled")")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        feedingShortcut.unregister()
        allSurfaces().forEach { $0.isPaused = true }
    }

    private func createMainMenu() {
        let menu = NSMenu()
        let root = NSMenuItem()
        let app = NSMenu(title: "Stillwater")
        app.addItem(withTitle: "Stillwater Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        app.addItem(withTitle: "Feed Fish", action: #selector(feedFish), keyEquivalent: "f").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Stillwater", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = app; menu.addItem(root)
        let editRoot = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: selector, keyEquivalent: key)
        }
        editRoot.submenu = edit; menu.addItem(editRoot)
        let windowRoot = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowRoot.submenu = window; menu.addItem(windowRoot)
        NSApp.mainMenu = menu
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "fish.fill", accessibilityDescription: "Stillwater aquarium settings")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "Stillwater — your aquarium"
        statusItem = item
        updateMenu(store.configuration)
    }

    private func updateMenu(_ config: AquariumConfiguration) {
        let menu = NSMenu()
        let title = NSMenuItem(title: "Stillwater · \(config.totalFish) fish", action: nil, keyEquivalent: "")
        title.isEnabled = false; menu.addItem(title)
        menu.addItem(withTitle: "Open Aquarium Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Open Preview", action: #selector(showPreview), keyEquivalent: "").target = self
        let feed = menu.addItem(withTitle: "Feed Fish", action: #selector(feedFish), keyEquivalent: "f")
        feed.target = self
        if store.feedingShortcutAvailable { feed.keyEquivalentModifierMask = [.control, .option, .command] }
        menu.addItem(.separator())
        for mode in AquariumMode.allCases {
            let item = NSMenuItem(title: mode == .live ? "Live aquarium" : "Still image", action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = mode.rawValue; item.state = config.mode == mode ? .on : .off
            menu.addItem(item)
        }
        let sceneItem = NSMenuItem(title: "Scene", action: nil, keyEquivalent: "")
        let scenes = NSMenu()
        for theme in AquariumTheme.allCases {
            let item = NSMenuItem(title: theme.title, action: #selector(selectScene(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = theme.rawValue; item.state = config.theme == theme ? .on : .off
            scenes.addItem(item)
        }
        sceneItem.submenu = scenes; menu.addItem(sceneItem)
        let lightingItem = NSMenuItem(title: "Day & Night", action: nil, keyEquivalent: "")
        let lightingMenu = NSMenu()
        for lighting in AquariumLighting.allCases {
            let item = NSMenuItem(title: lighting.title, action: #selector(selectLighting(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = lighting.rawValue
            item.state = config.lightingMode == lighting ? .on : .off
            lightingMenu.addItem(item)
        }
        lightingItem.submenu = lightingMenu; menu.addItem(lightingItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Save Aquarium as PNG…", action: #selector(exportPNG), keyEquivalent: "").target = self
        menu.addItem(withTitle: config.wallpaperEnabled ? "Hide Desktop Aquarium" : "Show Desktop Aquarium", action: #selector(toggleDesktop), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Stillwater", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let mode = AquariumMode(rawValue: value) else { return }
        var next = store.configuration; next.mode = mode; next.wallpaperEnabled = true; store.configuration = next
    }
    @objc private func selectScene(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let theme = AquariumTheme(rawValue: value) else { return }
        store.configuration.theme = theme
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(feedFish) ? store.canFeed : true
    }

    @objc private func feedFish() { store.requestFeed() }

    @objc private func selectLighting(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let lighting = AquariumLighting(rawValue: raw) else { return }
        store.configuration.lighting = lighting
    }
    @objc private func toggleDesktop() { store.configuration.wallpaperEnabled.toggle() }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1090, height: 840), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Stillwater"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 1000, height: 750)
        window.delegate = self
        let view = SettingsView(store: store,
            previewAction: { [weak self] in self?.showPreview() },
            exportAction: { [weak self] in self?.exportPNG() },
            desktopStillAction: { [weak self] in self?.setNativeStill() })
        window.contentView = NSHostingView(rootView: view)
        window.center()
        return window
    }

    @objc func showSettings() {
        if settingsWindow == nil { settingsWindow = makeSettingsWindow() }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshPauseState()
    }

    @objc func showPreview() {
        if previewWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 630), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Stillwater · Aquarium Preview"
            window.contentView = AquariumSurface(frame: NSRect(x: 0, y: 0, width: 1120, height: 630), configuration: store.configuration)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.minSize = NSSize(width: 640, height: 360)
            window.center()
            previewWindow = window
        }
        previewWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshPauseState()
    }

    private func makeDesktopWindow(for screen: NSScreen, config: AquariumConfiguration) -> DesktopWindow {
        let window = DesktopWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        window.setFrame(screen.frame, display: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isOpaque = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.title = "Stillwater Desktop"
        window.delegate = self
        window.contentView = AquariumSurface(frame: NSRect(origin: .zero, size: screen.frame.size), configuration: config)
        return window
    }

    private func rebuildDesktop(_ config: AquariumConfiguration) {
        for window in desktopWindows { (window.contentView as? AquariumSurface)?.isPaused = true; window.orderOut(nil); window.close() }
        desktopWindows.removeAll()
        lastDisplayMode = config.allDisplays
        lastWallpaperEnabled = config.wallpaperEnabled
        guard config.wallpaperEnabled else { return }
        let screens = config.allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        for screen in screens {
            let window = makeDesktopWindow(for: screen, config: config)
            desktopWindows.append(window)
            window.orderFrontRegardless()
        }
        refreshPauseState()
    }

    private func apply(_ config: AquariumConfiguration) {
        if config.usesGlobalFeedingShortcut && reviewDirectory == nil {
            let available = feedingShortcut.register { [weak self] in self?.store.requestFeed() }
            if available != store.feedingShortcutAvailable { store.feedingShortcutAvailable = available }
        } else {
            feedingShortcut.unregister()
            if store.feedingShortcutAvailable { store.feedingShortcutAvailable = false }
        }
        if lastDisplayMode != config.allDisplays || lastWallpaperEnabled != config.wallpaperEnabled { rebuildDesktop(config) }
        for window in desktopWindows { (window.contentView as? AquariumSurface)?.apply(config) }
        (previewWindow?.contentView as? AquariumSurface)?.apply(config)
        updateMenu(config)
        refreshPauseState()
    }

    private func subscribeToSystem() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in guard let self else { return }; self.rebuildDesktop(self.store.configuration) }.store(in: &subscriptions)
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, reason, paused) in [
            (NSWorkspace.screensDidSleepNotification, "display", true), (NSWorkspace.screensDidWakeNotification, "display", false),
            (NSWorkspace.willSleepNotification, "sleep", true), (NSWorkspace.didWakeNotification, "sleep", false),
            (NSWorkspace.sessionDidResignActiveNotification, "session", true), (NSWorkspace.sessionDidBecomeActiveNotification, "session", false)
        ] {
            workspace.publisher(for: name).receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self else { return }
                if paused { self.pauseReasons.insert(reason) } else { self.pauseReasons.remove(reason) }
                self.refreshPauseState()
            }.store(in: &subscriptions)
        }
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
            NotificationCenter.default.publisher(for: name).receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self else { return }
                self.allSurfaces().forEach { $0.apply(self.store.configuration) }
                self.refreshPauseState()
            }.store(in: &subscriptions)
        }
    }

    private func surfaces(in view: NSView?) -> [AquariumSurface] {
        guard let view else { return [] }
        if let surface = view as? AquariumSurface { return [surface] }
        return view.subviews.flatMap { surfaces(in: $0) }
    }
    private func allSurfaces() -> [AquariumSurface] {
        (desktopWindows as [NSWindow] + [settingsWindow, previewWindow].compactMap { $0 }).flatMap { surfaces(in: $0.contentView) }
    }
    private func refreshPauseState() {
        let systemPaused = !pauseReasons.isEmpty || ProcessInfo.processInfo.thermalState == .critical
        for window in desktopWindows as [NSWindow] + [settingsWindow, previewWindow].compactMap({ $0 }) {
            let hidden = !window.isVisible || window.isMiniaturized || !window.occlusionState.contains(.visible)
            for surface in surfaces(in: window.contentView) {
                let paused = systemPaused || hidden
                if surface.externallyPaused != paused { surface.externallyPaused = paused }
            }
        }
    }
    func windowDidChangeOcclusionState(_ notification: Notification) { refreshPauseState() }
    func windowDidMiniaturize(_ notification: Notification) { refreshPauseState() }
    func windowDidDeminiaturize(_ notification: Notification) { refreshPauseState() }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow { surfaces(in: window.contentView).forEach { $0.externallyPaused = true } }
    }

    private func snapshotData(for screen: NSScreen? = nil) -> Data? {
        let display = screen ?? NSScreen.screens.first
        let pixels = display.map { CGSize(width: $0.frame.width * $0.backingScaleFactor, height: $0.frame.height * $0.backingScaleFactor) } ?? CGSize(width: 1920, height: 1080)
        let source = desktopWindows.first(where: { $0.screen == display })?.contentView as? AquariumSurface
            ?? surfaces(in: settingsWindow?.contentView).first
            ?? previewWindow?.contentView as? AquariumSurface
        let surface = AquariumSurface(frame: CGRect(origin: .zero, size: pixels), configuration: store.configuration)
        if let source { surface.aquarium.restoreSimulation(source.aquarium.simulation) }
        surface.isPaused = true
        return surface.pngData()
    }

    @objc func exportPNG() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.title = "Save a moment"
        panel.nameFieldStringValue = "Stillwater-\(store.configuration.theme.rawValue).png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let data = snapshotData() else { throw AquariumError.snapshot }
            try data.write(to: url, options: .atomic)
            store.message = "Saved \(url.lastPathComponent)."
        } catch { present(error) }
    }

    private func setNativeStill() {
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Stillwater/Stills", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let screens = store.configuration.allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
            for screen in screens {
                guard let data = snapshotData(for: screen) else { throw AquariumError.snapshot }
                let url = directory.appendingPathComponent("\(store.configuration.theme.rawValue)-\(UUID().uuidString).png")
                try data.write(to: url, options: .atomic)
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true])
            }
            var next = store.configuration; next.mode = .still; next.wallpaperEnabled = false; store.configuration = next
            store.message = "Saved as your macOS wallpaper. It stays even when Stillwater quits."
        } catch { present(error) }
    }

    private func present(_ error: Error) {
        store.message = error.localizedDescription
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    private func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    private func verifyProductionControls(at directory: URL) async throws -> [String: Any] {
        subscribeToSystem()
        store.feedRequests.sink { [weak self] in self?.allSurfaces().forEach { $0.aquarium.feed() } }.store(in: &subscriptions)
        store.$configuration.dropFirst().sink { [weak self] next in self?.apply(next) }.store(in: &subscriptions)
        store.configuration = AquariumConfiguration()
        try await Task.sleep(for: .milliseconds(300))
        guard desktopWindows.count == NSScreen.screens.count, desktopWindows.allSatisfy({ $0.isVisible }) else { throw AquariumError.review("Desktop show failed") }
        let desktopIDs = Set(desktopWindows.map { Int($0.windowNumber) })
        let listed = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? [])
            .filter { desktopIDs.contains($0[kCGWindowNumber as String] as? Int ?? -1) }
        var checks: [String: Any] = ["desktopWindowsShown": desktopWindows.count, "desktopWindowsListedByWindowServer": listed.count]

        store.configuration.mode = .still
        try await Task.sleep(for: .milliseconds(250))
        guard desktopWindows.allSatisfy({ ($0.contentView as? AquariumSurface)?.isPaused == true }) else { throw AquariumError.review("Production Still control failed") }
        var changed = store.configuration
        changed.theme = .spring
        for species in FishSpecies.allCases { changed.setCount(species, species == .pearl ? 1 : 0) }
        store.configuration = changed
        try await Task.sleep(for: .milliseconds(250))
        guard desktopWindows.allSatisfy({ ($0.contentView as? AquariumSurface)?.aquarium.simulation.fish.count == 1 && ($0.contentView as? AquariumSurface)?.aquarium.configuration.theme == .spring }) else { throw AquariumError.review("Scene/population changes in still mode failed") }
        checks["sceneAndPopulationChangeWhileStill"] = true
        var dimensions: [[String: Any]] = []
        for enabled in [true, false] {
            store.configuration.wallpaperEnabled = enabled
            guard let data = snapshotData(), let bitmap = NSBitmapImageRep(data: data), let screen = NSScreen.screens.first else { throw AquariumError.snapshot }
            guard bitmap.pixelsWide == Int(screen.frame.width * screen.backingScaleFactor), bitmap.pixelsHigh == Int(screen.frame.height * screen.backingScaleFactor) else { throw AquariumError.review("Still export is not display resolution") }
            dimensions.append(["desktopEnabled": enabled, "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh])
        }
        checks["exportDimensions"] = dimensions
        guard desktopWindows.isEmpty else { throw AquariumError.review("Desktop hide failed") }
        store.configuration = AquariumConfiguration()
        guard desktopWindows.count == NSScreen.screens.count else { throw AquariumError.review("Desktop re-enable failed") }

        showPreview()
        guard let surface = previewWindow?.contentView as? AquariumSurface else { throw AquariumError.snapshot }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        try await Task.sleep(for: .milliseconds(250))
        guard surface.isPaused else { throw AquariumError.review("Sleep notification did not pause rendering") }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(250))
        guard !surface.isPaused else { throw AquariumError.review("Wake notification did not resume rendering") }
        checks["syntheticDisplaySleepWakeNotifications"] = true
        previewWindow?.performClose(nil)
        try await Task.sleep(for: .milliseconds(250))
        guard surface.isPaused else { throw AquariumError.review("Closed preview kept rendering") }
        showPreview()
        try await Task.sleep(for: .milliseconds(250))
        guard !surface.isPaused else { throw AquariumError.review("Reopened preview stayed paused") }
        checks["closeReopenPreview"] = true
        let shortcut = FeedingShortcut()
        let shortcutRegistered = shortcut.register { [weak self] in self?.store.requestFeed() }
        defer { shortcut.unregister() }
        checks["globalFeedingShortcutRegistered"] = shortcutRegistered
        if shortcutRegistered {
            guard shortcut.dispatchForReview() else { throw AquariumError.review("Global feed handler did not dispatch") }
            try await Task.sleep(for: .milliseconds(100))
            checks["globalFeedingShortcutDispatch"] = true
            shortcut.unregister()
            guard !shortcut.isRegistered && !shortcut.dispatchForReview() else { throw AquariumError.review("Global shortcut did not unregister") }
            checks["globalFeedingShortcutUnregister"] = true
            guard shortcut.register(action: { [weak self] in self?.store.requestFeed() }) else { throw AquariumError.review("Global shortcut did not re-register") }
            checks["globalFeedingShortcutReregister"] = true
            shortcut.unregister()
        } else {
            checks["globalFeedingShortcutLimit"] = "Registration unavailable; another running app may own the combination"
            store.requestFeed()
        }
        checks["shortcutTestScope"] = "Real OS shortcut registration and dispatch through its Carbon handler; no synthetic system key presses or input monitoring"
        guard allSurfaces().allSatisfy({ $0.aquarium.simulation.food.count + $0.aquarium.simulation.pendingFood.count == 12 }) else { throw AquariumError.review("Feed action did not reach every aquarium") }
        surface.aquarium.advanceForReview(seconds: 2)
        let responders = surface.aquarium.simulation.fish.filter { $0.feeding?.phase == .approaching || $0.feeding?.phase == .nibbling }
        guard !responders.isEmpty else { throw AquariumError.review("Fish did not react promptly to feeding") }
        checks["feedingRespondersWithinTwoSeconds"] = responders.count
        if let image = surface.pngData() { try image.write(to: directory.appendingPathComponent("feeding-response.png")) }
        surface.aquarium.advanceForReview(seconds: 58)
        guard surface.aquarium.simulation.mealsEaten > 0 else { throw AquariumError.review("Rendered fish did not eat food") }
        checks["productionFeedAction"] = true
        checks["mealsEatenDuringFeedingCheck"] = surface.aquarium.simulation.mealsEaten

        let originalAppearance = NSApp.appearance
        defer { NSApp.appearance = originalAppearance }
        store.configuration.mode = .still
        let frozenFish = surface.aquarium.simulation.fish.map { [$0.x, $0.y, $0.yaw, $0.finPhase] }
        for (appearance, expectedNight) in [(NSAppearance.Name.darkAqua, 1.0), (.aqua, 0.0)] {
            NSApp.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(350))
            guard allSurfaces().allSatisfy({ $0.aquarium.nightAmount == expectedNight && $0.isPaused }) else { throw AquariumError.review("Automatic appearance change did not repaint paused aquariums") }
        }
        guard frozenFish == surface.aquarium.simulation.fish.map({ [$0.x, $0.y, $0.yaw, $0.finPhase] }) else { throw AquariumError.review("Appearance change moved still fish") }
        store.configuration.lighting = .night
        guard surface.aquarium.nightAmount == 1 else { throw AquariumError.review("Manual night override failed") }
        NSApp.appearance = NSAppearance(named: .darkAqua)
        store.configuration.lighting = .day
        try await Task.sleep(for: .milliseconds(200))
        guard surface.aquarium.nightAmount == 0 else { throw AquariumError.review("Manual day override failed") }
        store.configuration.lighting = .system
        guard surface.aquarium.nightAmount == 1 else { throw AquariumError.review("Return to automatic lighting failed") }
        checks["systemAppearanceObservationWhileStill"] = true
        checks["dayNightOverrides"] = true
        checks["appearanceChangeKeepsFishFrozen"] = true
        checks["appearanceTestScope"] = "AppKit appearance overrides exercise the production KVO observer; macOS global appearance preferences were not changed"
        store.configuration.mode = .live
        NSApp.appearance = NSAppearance(named: .aqua)
        try await Task.sleep(for: .milliseconds(500))
        guard surface.aquarium.nightAmount > 0 && surface.aquarium.nightAmount < 1 else { throw AquariumError.review("Live day/night transition did not fade") }
        checks["liveLightingTransitionFades"] = true
        NSApp.appearance = originalAppearance
        try await Task.sleep(for: .milliseconds(300))

        // Brief CPU samples are measurements of this review process, not a battery-life promise.
        let liveCPU = cpuSeconds(), liveStart = ProcessInfo.processInfo.systemUptime, liveFrames = surface.aquarium.frameCount
        try await Task.sleep(for: .seconds(3))
        let liveDuration = ProcessInfo.processInfo.systemUptime - liveStart
        checks["sampleLiveCPUPercentOfOneCore"] = (cpuSeconds() - liveCPU) / liveDuration * 100
        checks["sampleLivePreviewFPS"] = Double(surface.aquarium.frameCount - liveFrames) / liveDuration
        store.configuration.mode = .still
        try await Task.sleep(for: .milliseconds(300))
        let stillCPU = cpuSeconds(), stillStart = ProcessInfo.processInfo.systemUptime, stillFrames = surface.aquarium.frameCount
        try await Task.sleep(for: .seconds(3))
        let stillDuration = ProcessInfo.processInfo.systemUptime - stillStart
        checks["sampleStillCPUPercentOfOneCore"] = (cpuSeconds() - stillCPU) / stillDuration * 100
        checks["stillFramesRenderedDuringSample"] = surface.aquarium.frameCount - stillFrames
        guard surface.aquarium.frameCount == stillFrames else { throw AquariumError.review("Still renderer consumed animation frames") }
        checks["sampleDurationSecondsPerMode"] = 3
        checks["sampleContext"] = "Review process with production desktop windows and a visible 1120x630 preview; not a sustained power benchmark"
        checks["manualChecksNotPerformed"] = ["Finder icon dragging", "Mission Control / Spaces switching", "Stage Manager", "physical display hotplug", "real sleep/wake", "native wallpaper installation"]
        return checks
    }

    private func runReview(at directory: URL) {
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { fputs("Review folder error: \(error)\n", stderr); NSApp.terminate(nil); return }
        settingsWindow = makeSettingsWindow()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor [self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
                var report: [String: Any] = ["screens": NSScreen.screens.map { ["width": $0.frame.width, "height": $0.frame.height, "scale": $0.backingScaleFactor] }]
                var sceneReports: [[String: Any]] = []
                for theme in AquariumTheme.allCases {
                    var config = AquariumConfiguration(); config.theme = theme; config.lighting = .day
                    let surface = AquariumSurface(frame: CGRect(x: 0, y: 0, width: 1600, height: 900), configuration: config)
                    surface.aquarium.advanceForReview(seconds: 12)
                    surface.isPaused = true
                    guard let data = surface.pngData() else { throw AquariumError.snapshot }
                    try data.write(to: directory.appendingPathComponent("\(theme.rawValue).png"))
                    sceneReports.append(["theme": theme.rawValue, "fish": surface.aquarium.simulation.fish.count, "bytes": data.count])
                    config.lighting = .night; config.mode = .still
                    surface.apply(config)
                    guard let night = surface.pngData(), night != data else { throw AquariumError.review("Night scene must render differently from daylight") }
                    try night.write(to: directory.appendingPathComponent("\(theme.rawValue)-night.png"))
                    config.counts = Dictionary(uniqueKeysWithValues: FishSpecies.allCases.map { ($0.rawValue, 0) })
                    surface.apply(config)
                    guard surface.aquarium.simulation.fish.isEmpty else { throw AquariumError.review("Zero population did not remove every fish") }
                }
                report["scenes"] = sceneReports
                var motionConfig = store.configuration; motionConfig.bubbles = true; motionConfig.lighting = .day
                let motion = AquariumSurface(frame: CGRect(x: 0, y: 0, width: 1200, height: 675), configuration: motionConfig)
                motion.aquarium.advanceForReview(seconds: 20)
                motion.aquarium.feed()
                let animationURL = directory.appendingPathComponent("motion-and-feeding.gif")
                if let destination = CGImageDestinationCreateWithURL(animationURL as CFURL, UTType.gif.identifier as CFString, 90, nil) {
                    CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
                    for _ in 0..<90 {
                        motion.aquarium.advanceForReview(seconds: 1.0 / 15)
                        guard let data = motion.pngData(), let image = NSBitmapImageRep(data: data)?.cgImage else { throw AquariumError.snapshot }
                        CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 15]] as CFDictionary)
                    }
                    guard CGImageDestinationFinalize(destination) else { throw AquariumError.review("Motion capture failed") }
                    report["motionCapture"] = "6 seconds of production simulation and body/turn shader, sampled at 15fps"
                }
                if let screen = NSScreen.screens.first {
                    let window = makeDesktopWindow(for: screen, config: store.configuration)
                    guard window.ignoresMouseEvents && !window.canBecomeKey && window.level.rawValue < Int(CGWindowLevelForKey(.desktopIconWindow)) else { throw AquariumError.review("Desktop window properties are incorrect") }
                    report["desktopWindow"] = ["level": window.level.rawValue, "iconLevel": CGWindowLevelForKey(.desktopIconWindow), "ignoresMouseEvents": window.ignoresMouseEvents, "canBecomeKey": window.canBecomeKey, "allSpaces": window.collectionBehavior.contains(.canJoinAllSpaces)]
                    if let surface = window.contentView as? AquariumSurface {
                        surface.aquarium.advanceForReview(seconds: 12)
                        guard let data = surface.pngData() else { throw AquariumError.snapshot }
                        try data.write(to: directory.appendingPathComponent("actual-display.png"))
                    }
                    window.close()
                }
                // AppKit's bitmap cache excludes Metal layers. Use the renderer's own snapshot
                // in this capture-only preview; all controls and layout are the production view.
                let originalAppearance = NSApp.appearance
                for dark in [false, true] {
                    NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    let suffix = dark ? "-night" : ""
                    let preview = NSImage(contentsOf: directory.appendingPathComponent("\(store.configuration.theme.rawValue)\(suffix).png"))
                    for section in SettingsSection.allCases {
                        let root = SettingsView(store: store, previewAction: {}, exportAction: {}, desktopStillAction: {}, reviewPreview: preview, reviewSection: section)
                        settingsWindow?.contentView = NSHostingView(rootView: root)
                        try await Task.sleep(for: .milliseconds(250))
                        if let view = settingsWindow?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                            view.cacheDisplay(in: view.bounds, to: bitmap)
                            if let data = bitmap.representation(using: .png, properties: [:]) {
                                let name = section == .aquarium ? "settings" : "settings-\(section.id.replacingOccurrences(of: " ", with: "-").lowercased())"
                                try data.write(to: directory.appendingPathComponent("\(name)\(dark ? "-dark" : "-light").png"))
                            }
                        }
                    }
                }
                NSApp.appearance = originalAppearance
                report["settingsCapture"] = "Production layout with renderer snapshot substituted for Metal layer"
                var still = store.configuration; still.mode = .still
                let frozen = AquariumSurface(frame: CGRect(x: 0, y: 0, width: 800, height: 450), configuration: still)
                let before = frozen.aquarium.simulation.fish.map { [$0.x, $0.y] }
                frozen.aquarium.advanceForReview(seconds: 5)
                report["stillPositionsUnchanged"] = before == frozen.aquarium.simulation.fish.map { [$0.x, $0.y] }
                try await Task.sleep(for: .milliseconds(250))
                guard frozen.isPaused && before == frozen.aquarium.simulation.fish.map({ [$0.x, $0.y] }) else { throw AquariumError.review("Still mode did not freeze and pause") }
                report["stillRendererPaused"] = frozen.isPaused
                showPreview()
                guard let liveSurface = previewWindow?.contentView as? AquariumSurface else { throw AquariumError.snapshot }
                let liveTime = liveSurface.aquarium.simulation.time
                try await Task.sleep(for: .milliseconds(500))
                guard liveSurface.aquarium.simulation.time > liveTime else { throw AquariumError.review("On-screen rendering did not advance") }
                report["liveOnscreenAnimation"] = true
                liveSurface.apply(still)
                try await Task.sleep(for: .milliseconds(250))
                let frozenTime = liveSurface.aquarium.simulation.time
                try await Task.sleep(for: .milliseconds(250))
                guard liveSurface.isPaused && liveSurface.aquarium.simulation.time == frozenTime else { throw AquariumError.review("On-screen still mode continued rendering") }
                liveSurface.apply(store.configuration)
                try await Task.sleep(for: .milliseconds(250))
                guard !liveSurface.isPaused && liveSurface.aquarium.simulation.time > frozenTime else { throw AquariumError.review("Resume from still mode failed") }
                report["liveStillLiveTransition"] = true
                report["productionControls"] = try await verifyProductionControls(at: directory)
                report["result"] = "passed"
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("report.json"))
                print("Stillwater visual review complete: \(directory.path)")
                NSApp.terminate(nil)
            } catch {
                fputs("Review failed: \(error)\n", stderr)
                try? "\(error)".write(to: directory.appendingPathComponent("failure.txt"), atomically: true, encoding: .utf8)
                exit(1)
            }
        }
    }
}

enum AquariumError: LocalizedError {
    case snapshot, review(String)
    var errorDescription: String? {
        switch self { case .snapshot: return "The aquarium image could not be captured. Please open the preview and try again."; case .review(let reason): return reason }
    }
}
