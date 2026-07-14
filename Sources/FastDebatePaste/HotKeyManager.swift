import Carbon.HIToolbox
import Foundation

/// Registers system-wide hotkeys via the Carbon Event Manager (the
/// reliable, long-lived way to get global hotkeys on macOS) and
/// dispatches each to a Swift closure on the main thread.
final class HotKeyManager {
    static let shared = HotKeyManager()

    private struct Registration {
        let ref: EventHotKeyRef
        let handler: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = {
        // Four-char code 'FDPx' as the hotkey signature.
        let chars = "FDPx".utf8.prefix(4)
        return chars.reduce(0) { ($0 << 8) | OSType($1) }
    }()

    private init() {}

    /// Install the single application-wide Carbon event handler. Call
    /// once at launch before registering hotkeys.
    func installHandler() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, eventRef, _ in
            var hkID = EventHotKeyID()
            let status = GetEventParameter(eventRef,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hkID)
            if status == noErr {
                HotKeyManager.shared.fire(id: hkID.id)
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(),
                            callback,
                            1,
                            &spec,
                            nil,
                            &eventHandler)
    }

    /// Register a hotkey described by a config string. Returns true on
    /// success. Re-registering replaces nothing automatically — call
    /// unregisterAll() first when reloading config.
    @discardableResult
    func register(_ keyString: String, handler: @escaping () -> Void) -> Bool {
        guard let stroke = Keys.parse(keyString) else {
            NSLog("FastDebatePaste: cannot register unparseable hotkey '\(keyString)'")
            return false
        }
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(UInt32(stroke.keyCode),
                                         stroke.carbonModifiers,
                                         hkID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref else {
            NSLog("FastDebatePaste: RegisterEventHotKey failed for '\(keyString)' (status \(status)) — likely already taken by another app")
            return false
        }
        registrations[id] = Registration(ref: ref, handler: handler)
        return true
    }

    func unregisterAll() {
        for (_, reg) in registrations {
            UnregisterEventHotKey(reg.ref)
        }
        registrations.removeAll()
    }

    private func fire(id: UInt32) {
        guard let reg = registrations[id] else { return }
        DispatchQueue.main.async { reg.handler() }
    }
}
