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
    // Members without `private` are also used by the `--review` extension in ReviewMode.swift.
    var settingsWindow: NSWindow?
    var previewWindow: NSWindow?
    var desktopWindows: [DesktopWindow] = []
    private var statusItem: NSStatusItem?
    private let feedingShortcut = FeedingShortcut()
    var subscriptions: Set<AnyCancellable> = []
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

    func makeSettingsWindow() -> NSWindow {
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

    func makeDesktopWindow(for screen: NSScreen, config: AquariumConfiguration) -> DesktopWindow {
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

    func apply(_ config: AquariumConfiguration) {
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

    func subscribeToSystem() {
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
    func allSurfaces() -> [AquariumSurface] {
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

    func snapshotData(for screen: NSScreen? = nil) -> Data? {
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
            let directory = try WallpaperStills.folder()
            let screens = store.configuration.allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
            var written: [URL] = []
            for screen in screens {
                guard let data = snapshotData(for: screen) else { throw AquariumError.snapshot }
                // A fresh name makes macOS reload the wallpaper instead of keeping a cached image.
                let url = directory.appendingPathComponent("\(store.configuration.theme.rawValue)-\(UUID().uuidString).png")
                try data.write(to: url, options: .atomic)
                written.append(url)
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true])
            }
            let inUse = NSScreen.screens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0) }
            WallpaperStills.prune(in: directory, keeping: written + inUse)
            var next = store.configuration; next.mode = .still; next.wallpaperEnabled = false; store.configuration = next
            store.message = "Saved as your macOS wallpaper. It stays even when Stillwater quits."
        } catch { present(error) }
    }

    private func present(_ error: Error) {
        store.message = error.localizedDescription
        let alert = NSAlert(error: error)
        alert.runModal()
    }

}

enum AquariumError: LocalizedError {
    case snapshot, review(String)
    var errorDescription: String? {
        switch self { case .snapshot: return "The aquarium image could not be captured. Please open the preview and try again."; case .review(let reason): return reason }
    }
}
