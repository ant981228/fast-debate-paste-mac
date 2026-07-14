import Foundation

/// User-editable configuration, persisted as JSON in
/// ~/Library/Application Support/FastDebatePaste/config.json.
///
/// Mirrors the Hotkeys.ini idea from the original AutoHotkey script,
/// adapted for macOS: Cmd instead of Ctrl, and only the essentials —
/// the three paste actions, the target picker, and the CardMirror
/// bridge knobs.
struct Config: Codable {
    // ── Global hotkeys (what you press anywhere to trigger an action) ──
    // Ctrl+Shift mirrors the original Windows bindings and avoids
    // clobbering Mac system shortcuts like Cmd+Shift+V (paste & match
    // style). The copy key below stays Cmd-based because it is the real
    // Mac shortcut it drives in the source app.
    var selectTargetWindow = "ctrl+shift+w"
    var performCopyPaste = "ctrl+shift+c"
    var performCopyPasteNoLineBreaks = "ctrl+shift+v"
    var performCopyPasteNoLineBreaksNoReturn = "ctrl+shift+b"
    var showHelp = "ctrl+shift+h"

    // ── Source-app copy shortcut (sent to the app you copy FROM) ──
    /// Standard copy in the source app.
    var copyKey = "cmd+c"

    // Note: the keystroke-fallback paste into the target is NOT
    // configurable — it is always Return + F2 (CardMirror's default
    // "Paste Plain Text"). The native HTTP bridge makes the fallback
    // rare; keeping it fixed removes a whole class of misconfiguration.

    // ── Behavior ──
    /// Start automatically when you log in. Synced to the system login
    /// item via SMAppService on launch and whenever toggled in the menu.
    var launchAtLogin = false

    // ── CardMirror native integration ──
    /// How to deliver into CardMirror:
    ///   "auto"      — try the native HTTP bridge; if it's unavailable or
    ///                 refuses, silently fall back to keystrokes (default;
    ///                 a paste is never lost)
    ///   "http"      — bridge only, NO fallback; if the native insert
    ///                 doesn't go through, surface an error instead of
    ///                 pasting via keystrokes (use this to verify the
    ///                 bridge actually works — keystroke fallback would
    ///                 otherwise mask a broken bridge)
    ///   "keystroke" — never use the bridge; always synthesize keystrokes
    var integrationMode = "auto"
    /// Where CardMirror writes its bridge discovery file (port + token).
    var discoveryFilePath = "~/Library/Application Support/CardMirror/fast-paste-bridge.json"
    /// Only offer windows from this app in the target picker (per spec §1).
    /// Empty string = offer all windows.
    var targetAppMatch = "CardMirror"
    var httpPingTimeoutMs = 1000
    var httpInsertTimeoutMs = 1500
    /// Delay after activating CardMirror before the HTTP insert, to let
    /// Electron register window focus.
    var httpActivateSettleMs = 120

    // ── Timing knobs (milliseconds) ──
    var activateDelayMs = 200
    var pasteDelayMs = 200
    /// How long to wait for the clipboard to fill after a copy.
    var copyTimeoutMs = 2000

    // MARK: - Persistence

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("FastDebatePaste", isDirectory: true)
    }

    static var fileURL: URL {
        directory.appendingPathComponent("config.json")
    }

    /// Load config from disk, creating it with defaults on first run.
    /// Decoding is lenient: unknown/missing keys fall back to defaults
    /// because every property has a default value and we re-encode.
    static func load() -> Config {
        let url = fileURL
        guard let data = try? Data(contentsOf: url) else {
            let fresh = Config()
            fresh.save()
            return fresh
        }
        do {
            let decoder = JSONDecoder()
            let loaded = try decoder.decode(Config.self, from: data)
            return loaded
        } catch {
            NSLog("FastDebatePaste: config.json unreadable (\(error)); using defaults")
            return Config()
        }
    }

    func save() {
        try? FileManager.default.createDirectory(at: Config.directory,
                                                 withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(self) {
            try? data.write(to: Config.fileURL)
        }
    }
}

// MARK: - Forward/backward-compatible decoding
//
// Swift's synthesized decoder throws on any missing key, which would
// reset the WHOLE config whenever a new field is added (or a user
// deletes a line). Decoding each field with `decodeIfPresent`, falling
// back to the default value, makes config.json tolerant of additions,
// removals, and partial edits. Implemented in an extension so the
// memberwise `init()` and synthesized `encode(to:)` are preserved.
extension Config {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()  // source of default values
        func s(_ k: CodingKeys, _ def: String) -> String {
            (try? c.decodeIfPresent(String.self, forKey: k)) .flatMap { $0 } ?? def
        }
        func b(_ k: CodingKeys, _ def: Bool) -> Bool {
            (try? c.decodeIfPresent(Bool.self, forKey: k)) .flatMap { $0 } ?? def
        }
        func i(_ k: CodingKeys, _ def: Int) -> Int {
            (try? c.decodeIfPresent(Int.self, forKey: k)) .flatMap { $0 } ?? def
        }

        selectTargetWindow = s(.selectTargetWindow, d.selectTargetWindow)
        performCopyPaste = s(.performCopyPaste, d.performCopyPaste)
        performCopyPasteNoLineBreaks = s(.performCopyPasteNoLineBreaks, d.performCopyPasteNoLineBreaks)
        performCopyPasteNoLineBreaksNoReturn = s(.performCopyPasteNoLineBreaksNoReturn, d.performCopyPasteNoLineBreaksNoReturn)
        showHelp = s(.showHelp, d.showHelp)

        copyKey = s(.copyKey, d.copyKey)

        launchAtLogin = b(.launchAtLogin, d.launchAtLogin)

        integrationMode = s(.integrationMode, d.integrationMode)
        discoveryFilePath = s(.discoveryFilePath, d.discoveryFilePath)
        targetAppMatch = s(.targetAppMatch, d.targetAppMatch)
        httpPingTimeoutMs = i(.httpPingTimeoutMs, d.httpPingTimeoutMs)
        httpInsertTimeoutMs = i(.httpInsertTimeoutMs, d.httpInsertTimeoutMs)
        httpActivateSettleMs = i(.httpActivateSettleMs, d.httpActivateSettleMs)

        activateDelayMs = i(.activateDelayMs, d.activateDelayMs)
        pasteDelayMs = i(.pasteDelayMs, d.pasteDelayMs)
        copyTimeoutMs = i(.copyTimeoutMs, d.copyTimeoutMs)
    }
}
