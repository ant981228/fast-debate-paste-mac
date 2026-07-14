import AppKit

/// The copy → process → paste engine. Ports PerformCopyPaste and its
/// variants from the original AutoHotkey script.
final class PasteActions {
    static let shared = PasteActions()

    /// Keystroke-fallback paste chord: F2 = CardMirror's default
    /// "Paste Plain Text". Fixed on purpose — the native bridge is the
    /// primary path, and a configurable fallback key was one more
    /// thing to misconfigure.
    private static let fallbackPasteKey = "f2"
    private static let fallbackReturnKey = "enter"

    /// Per-action behavior.
    private struct Options {
        var stripBreaks: Bool
        var pressReturn: Bool
        var prependSpace: Bool
        // Native-integration intent (used by the HTTP bridge path).
        var role: CardMirrorClient.Role
        var newParagraph: Bool
    }

    private let queue = DispatchQueue(label: "com.fastdebatepaste.actions")
    private let pasteboard = NSPasteboard.general

    private init() {}

    // MARK: - Public entry points (called on the main thread)

    func performCopyPaste() {
        run(Options(stripBreaks: false, pressReturn: true, prependSpace: false,
                    role: .card, newParagraph: true))
    }

    func performCopyPasteNoLineBreaks() {
        run(Options(stripBreaks: true, pressReturn: true, prependSpace: false,
                    role: .card, newParagraph: true))
    }

    func performCopyPasteNoLineBreaksNoReturn() {
        run(Options(stripBreaks: true, pressReturn: false, prependSpace: true,
                    role: .inline, newParagraph: false))
    }

    // MARK: - Core

    private func run(_ opts: Options) {
        // Snapshot everything we need from the main thread.
        let cfg = AppState.shared.config
        guard let target = AppState.shared.target else {
            Alerts.info("Please select a target window first using \(cfg.selectTargetWindow).")
            return
        }
        guard WindowTargeting.stillExists(target) else {
            AppState.shared.target = nil
            Alerts.info("The target window is no longer available. Please select a new target window using \(cfg.selectTargetWindow).")
            return
        }
        let sourcePID = WindowTargeting.frontmostPID()

        queue.async {
            // 1. Copy from the source app.
            let cleared = self.pasteboard.clearContents()
            usleep(30_000)
            Keyboard.tap(string: cfg.copyKey)

            guard self.waitForClipboard(afterChangeCount: cleared, timeoutMs: cfg.copyTimeoutMs) else {
                Alerts.info("Failed to copy from the source app. Please try again.")
                return
            }
            let original = self.pasteboard.string(forType: .string) ?? ""

            // 2. Process the text.
            var processed = TextProcessor.process(original)
            let wasProcessed = (processed != original)
            if opts.stripBreaks {
                processed = TextProcessor.stripLineBreaks(processed)
            }
            if opts.prependSpace {
                processed = " " + processed
            }

            // 3. Deliver into CardMirror per integration mode.
            if cfg.integrationMode == "keystroke" {
                self.deliverViaKeystrokes(text: processed, opts: opts,
                                          target: target, cfg: cfg)
            } else if case .fallback(let reason) = self.deliverViaHTTP(
                text: processed, opts: opts, omitted: wasProcessed,
                target: target, cfg: cfg) {
                // Bridge didn't deliver. In "auto" we fall back to
                // keystrokes; in "http" (strict) we surface the failure
                // instead, so a broken bridge is visible rather than
                // silently masked.
                if cfg.integrationMode == "http" {
                    Alerts.info("Native CardMirror insert didn't go through (\(reason)). "
                        + "integrationMode is \"http\", so no keystroke fallback was attempted — "
                        + "set it to \"auto\" to fall back automatically.")
                } else {
                    self.deliverViaKeystrokes(text: processed, opts: opts,
                                              target: target, cfg: cfg)
                }
            }

            // 4. Return focus to the source app.
            if sourcePID > 0 {
                NSRunningApplication(processIdentifier: sourcePID)?
                    .activate(options: [.activateIgnoringOtherApps])
            }
        }
    }

    /// Try the native CardMirror HTTP bridge. Activates the target window
    /// first so CardMirror's focused doc is the destination, then POSTs.
    /// Returns the bridge `Outcome`; the caller decides what a `.fallback`
    /// means based on the integration mode.
    private func deliverViaHTTP(text: String, opts: Options, omitted: Bool,
                                target: TargetWindow, cfg: Config) -> CardMirrorClient.Outcome {
        _ = WindowTargeting.activate(target, timeoutMs: 2000)
        usleep(useconds_t(cfg.httpActivateSettleMs * 1000))
        let outcome = CardMirrorClient.insert(text: text, role: opts.role,
                                              newParagraph: opts.newParagraph,
                                              omitted: omitted, config: cfg)
        if case .fallback(let reason) = outcome {
            NSLog("FastDebatePaste: native insert unavailable (\(reason))")
        }
        return outcome
    }

    /// The original keystroke path: activate, optional Return, paste via
    /// F2 (CardMirror's default "Paste Plain Text" — fixed, see
    /// `fallbackPasteKey`).
    private func deliverViaKeystrokes(text: String, opts: Options,
                                      target: TargetWindow, cfg: Config) {
        _ = WindowTargeting.activate(target, timeoutMs: 2000)
        if opts.pressReturn {
            Keyboard.tap(string: Self.fallbackReturnKey)
            usleep(useconds_t(cfg.activateDelayMs * 1000))
        }
        self.pasteboard.clearContents()
        self.pasteboard.setString(text, forType: .string)
        Keyboard.tap(string: Self.fallbackPasteKey)
        usleep(useconds_t(cfg.pasteDelayMs * 1000))
    }

    /// Wait until the clipboard's change count moves past `afterChangeCount`
    /// AND it holds non-empty text, or until the timeout elapses.
    private func waitForClipboard(afterChangeCount: Int, timeoutMs: Int) -> Bool {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline {
            if pasteboard.changeCount != afterChangeCount,
               let s = pasteboard.string(forType: .string), !s.isEmpty {
                return true
            }
            usleep(50_000)
        }
        return false
    }
}
