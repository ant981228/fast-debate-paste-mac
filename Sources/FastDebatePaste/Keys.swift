import Carbon.HIToolbox
import CoreGraphics

/// A parsed keystroke: a virtual key code plus modifier flags.
/// Used both for registering global hotkeys (Carbon) and for
/// synthesizing key presses into other apps (CGEvent).
struct KeyStroke: Equatable {
    var keyCode: UInt16
    /// Modifiers in CGEventFlags form (the synthesis side). The
    /// Carbon-registration side derives its own mask from these.
    var flags: CGEventFlags

    /// Carbon modifier mask (cmdKey/shiftKey/optionKey/controlKey)
    /// for RegisterEventHotKey.
    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if flags.contains(.maskCommand) { m |= UInt32(cmdKey) }
        if flags.contains(.maskShift) { m |= UInt32(shiftKey) }
        if flags.contains(.maskAlternate) { m |= UInt32(optionKey) }
        if flags.contains(.maskControl) { m |= UInt32(controlKey) }
        return m
    }
}

enum Keys {
    /// US-ANSI virtual key codes for the keys this app needs. Keyed by
    /// the lowercase token used in the config file.
    static let named: [String: UInt16] = [
        // letters
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37,
        "j": 38, "k": 40, "n": 45, "m": 46,
        // digits (top row)
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26,
        "8": 28, "9": 25, "0": 29,
        // punctuation
        "=": 24, "-": 27, "]": 30, "[": 33, "'": 39, ";": 41, "\\": 42,
        ",": 43, "/": 44, ".": 47, "`": 50,
        // named keys
        "return": 36, "enter": 36, "tab": 48, "space": 49,
        "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
        "forwarddelete": 117,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
        // function keys
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103,
        "f12": 111, "f13": 105, "f14": 107, "f15": 113,
    ]

    /// Parse a human-friendly hotkey string ("cmd+shift+c", "f10",
    /// "ctrl+0") into a KeyStroke. Returns nil if no key token is found.
    static func parse(_ raw: String) -> KeyStroke? {
        return parseTokens(simpleTokens(raw))
    }

    private static func simpleTokens(_ raw: String) -> [String] {
        // Split on "+", but tolerate a trailing literal "+" or "-" as
        // the key itself (e.g. "cmd++" or "cmd+-").
        var parts: [String] = []
        var current = ""
        for ch in raw {
            if ch == "+" && !current.isEmpty {
                parts.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    private static func parseTokens(_ tokens: [String]) -> KeyStroke? {
        var flags: CGEventFlags = []
        var keyCode: UInt16? = nil
        for tok in tokens {
            switch tok {
            case "cmd", "command", "⌘", "meta", "super", "win":
                flags.insert(.maskCommand)
            case "shift", "⇧":
                flags.insert(.maskShift)
            case "opt", "option", "alt", "⌥":
                flags.insert(.maskAlternate)
            case "ctrl", "control", "⌃":
                flags.insert(.maskControl)
            default:
                if let code = named[tok] {
                    keyCode = code
                }
            }
        }
        guard let code = keyCode else { return nil }
        return KeyStroke(keyCode: code, flags: flags)
    }
}
