import CoreGraphics
import Foundation

/// Synthesizes keystrokes into whatever app is frontmost, using
/// CGEvent. Requires the app to be trusted for Accessibility.
enum Keyboard {
    /// A shared event source. `.combinedSessionState` makes synthetic
    /// events honor the user's current modifier state sensibly.
    private static let source = CGEventSource(stateID: .combinedSessionState)

    /// Modifier virtual key codes (left + right Command/Shift/Option/
    /// Control). CapsLock (57) and Fn (63) are deliberately excluded —
    /// releasing CapsLock via synthesis can toggle its latched state.
    private static let modifierKeyCodes: [UInt16] = [54, 55, 56, 58, 59, 60, 61, 62]

    /// Press and release a key with the given modifier flags.
    ///
    /// Because actions are triggered by a global hotkey, the user is
    /// typically still physically holding the hotkey's modifiers
    /// (e.g. Ctrl+Shift) when this runs. Those held modifiers leak into
    /// the synthesized event and corrupt the intended chord — a
    /// synthesized Cmd+C arrives as Cmd+Ctrl+Shift+C and does nothing.
    /// So we first release any held modifiers, then post the chord with
    /// exactly the flags we want.
    static func tap(_ stroke: KeyStroke, holdMs: Int = 12) {
        // If the very key we're about to synthesize is still physically
        // held (e.g. the hotkey is Ctrl+Shift+C and we're synthesizing
        // Cmd+C), the synthetic press is swallowed — you can't "press" a
        // key the hardware already has down. Wait for it to come up.
        waitForKeyRelease(stroke.keyCode)
        clearHeldModifiers()
        post(keyCode: stroke.keyCode, flags: stroke.flags, keyDown: true)
        usleep(useconds_t(max(0, holdMs) * 1000))
        post(keyCode: stroke.keyCode, flags: stroke.flags, keyDown: false)
    }

    /// Parse a hotkey string and tap it. Returns false if it couldn't
    /// be parsed (caller can log/skip).
    @discardableResult
    static func tap(string: String, holdMs: Int = 12) -> Bool {
        guard let stroke = Keys.parse(string) else {
            NSLog("FastDebatePaste: unparseable keystroke '\(string)'")
            return false
        }
        tap(stroke, holdMs: holdMs)
        return true
    }

    /// Block (briefly) until `keyCode` is not physically pressed, so a
    /// synthesized press of it actually registers. Times out so a stuck
    /// or held key can't hang the action forever.
    private static func waitForKeyRelease(_ keyCode: UInt16, timeoutMs: Int = 1500) {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline {
            if !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode)) {
                return
            }
            usleep(10_000)
        }
    }

    /// Post key-up events for every modifier key so the window server
    /// stops treating the hotkey's still-held modifiers as part of the
    /// next synthesized chord. Posting an "up" for an already-up
    /// modifier is benign.
    private static func clearHeldModifiers() {
        for keyCode in modifierKeyCodes {
            guard let event = CGEvent(keyboardEventSource: source,
                                      virtualKey: keyCode,
                                      keyDown: false) else { continue }
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
        // Brief settle so the cleared state is in effect before the chord.
        usleep(8000)
    }

    private static func post(keyCode: UInt16, flags: CGEventFlags, keyDown: Bool) {
        guard let event = CGEvent(keyboardEventSource: source,
                                  virtualKey: keyCode,
                                  keyDown: keyDown) else { return }
        // Only set flags on key-down; the key-up carries none so the
        // modifiers are cleanly released.
        event.flags = keyDown ? flags : []
        event.post(tap: .cghidEventTap)
    }
}
