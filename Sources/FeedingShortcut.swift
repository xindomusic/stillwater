import AppKit
import Carbon

/// Registers one specific shortcut; it does not observe other keyboard input.
@MainActor final class FeedingShortcut {
    static let label = "⌃⌥⌘F"
    static let identifier = EventHotKeyID(signature: 0x53574644, id: 1) // SWFD
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?
    var isRegistered: Bool { hotKey != nil }

    @discardableResult func register(action: @escaping () -> Void) -> Bool {
        self.action = action
        if hotKey != nil { return true }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                  identifier.signature == 0x53574644, identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<FeedingShortcut>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor [weak shortcut] in shortcut?.action?() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { unregister(); return false }
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_F), UInt32(controlKey | optionKey | cmdKey),
                                         Self.identifier, GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey)
        if result != noErr { unregister(); return false }
        return true
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil; handler = nil; action = nil
    }

    /// Exercises the registered Carbon event handler without synthesizing system key presses.
    func dispatchForReview() -> Bool {
        guard isRegistered else { return false }
        var event: EventRef?
        guard CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), GetCurrentEventTime(), 0, &event) == noErr,
              let event else { return false }
        defer { ReleaseEvent(event) }
        var identifier = Self.identifier
        guard SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                MemoryLayout<EventHotKeyID>.size, &identifier) == noErr else { return false }
        return SendEventToEventTarget(event, GetApplicationEventTarget()) == noErr
    }
}
