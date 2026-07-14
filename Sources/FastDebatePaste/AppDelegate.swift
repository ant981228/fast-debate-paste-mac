import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var targetSubmenu: NSMenu!
    private var targetLineItem: NSMenuItem!
    private var accessibilityItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var accessibilityWatchTimer: Timer?
    private var didRelaunchForAccessibility = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)

        buildStatusItem()

        HotKeyManager.shared.installHandler()
        registerHotkeys()

        // Sync the system login item to the saved preference.
        applyLoginItemSetting()

        // Ask for Accessibility up front — nothing works without it.
        promptForAccessibilityIfNeeded()

        // A freshly granted Accessibility permission flips the trust check
        // live, but the CGEvent-posting privilege it gates doesn't activate
        // until the process restarts — so copy/paste would silently no-op
        // even though the menu reads "granted". If we launched untrusted,
        // watch for the grant and relaunch ourselves once, automatically.
        startAccessibilityWatchIfNeeded()
    }

    // MARK: - Status item & menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "doc.on.clipboard",
                                   accessibilityDescription: "Fast Debate Paste") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "FDP"
            }
        }

        let menu = NSMenu()
        menu.delegate = self

        targetLineItem = NSMenuItem(title: "Target: None", action: nil, keyEquivalent: "")
        targetLineItem.isEnabled = false
        menu.addItem(targetLineItem)

        let selectItem = NSMenuItem(title: "Select Target Window", action: nil, keyEquivalent: "")
        targetSubmenu = NSMenu()
        targetSubmenu.delegate = self
        selectItem.submenu = targetSubmenu
        menu.addItem(selectItem)

        menu.addItem(.separator())

        addAction(to: menu, title: "Copy-Paste",
                  action: #selector(menuCopyPaste))
        addAction(to: menu, title: "Copy-Paste (No Line Breaks)",
                  action: #selector(menuCopyPasteNoLineBreaks))
        addAction(to: menu, title: "Copy-Paste (No Line Breaks, No Return)",
                  action: #selector(menuCopyPasteNoLineBreaksNoReturn))

        menu.addItem(.separator())

        addAction(to: menu, title: "Help…", action: #selector(showHelp))
        addAction(to: menu, title: "Edit Config…", action: #selector(editConfig))
        addAction(to: menu, title: "Reload Config", action: #selector(reloadConfig))

        menu.addItem(.separator())

        launchAtLoginItem = NSMenuItem(title: "Launch at Login",
                                       action: #selector(toggleLaunchAtLogin),
                                       keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        accessibilityItem = NSMenuItem(title: "Accessibility: checking…",
                                       action: #selector(openAccessibilitySettings),
                                       keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        let quit = NSMenuItem(title: "Quit Fast Debate Paste",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func addAction(to menu: NSMenu, title: String, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === targetSubmenu {
            populateTargetSubmenu()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Refresh the target line and accessibility status each time the
        // main menu opens.
        if let target = AppState.shared.target {
            targetLineItem.title = "Target: \(target.label)"
        } else {
            targetLineItem.title = "Target: None"
        }
        let trusted = AXIsProcessTrusted()
        accessibilityItem.title = trusted
            ? "Accessibility: granted ✓"
            : "Accessibility: NOT granted — click to fix"

        // Reflect the real system state (the source of truth), in case
        // it was changed from System Settings → Login Items.
        launchAtLoginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    /// Windows offered in the target picker. Filtered to the configured
    /// app (CardMirror by default, per integration spec §1); an empty
    /// `targetAppMatch` offers all windows.
    private func targetWindows() -> [TargetWindow] {
        let match = AppState.shared.config.targetAppMatch
        let all = WindowTargeting.listWindows()
        guard !match.isEmpty else { return all }
        return all.filter { $0.appName.range(of: match, options: .caseInsensitive) != nil }
    }

    private func populateTargetSubmenu() {
        targetSubmenu.removeAllItems()
        let windows = targetWindows()
        guard !windows.isEmpty else {
            let item = NSMenuItem(title: "No windows found", action: nil, keyEquivalent: "")
            item.isEnabled = false
            targetSubmenu.addItem(item)
            return
        }
        for window in windows {
            let item = NSMenuItem(title: window.label,
                                  action: #selector(chooseTarget(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = Box(window)
            if window == AppState.shared.target { item.state = .on }
            targetSubmenu.addItem(item)
        }
    }

    /// NSMenuItem.representedObject needs a reference type; wrap the
    /// value-type TargetWindow.
    private final class Box {
        let value: TargetWindow
        init(_ value: TargetWindow) { self.value = value }
    }

    @objc private func chooseTarget(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? Box else { return }
        AppState.shared.target = box.value
    }

    // MARK: - Menu / hotkey actions

    @objc private func menuCopyPaste() { PasteActions.shared.performCopyPaste() }
    @objc private func menuCopyPasteNoLineBreaks() { PasteActions.shared.performCopyPasteNoLineBreaks() }
    @objc private func menuCopyPasteNoLineBreaksNoReturn() { PasteActions.shared.performCopyPasteNoLineBreaksNoReturn() }

    /// Hotkey-triggered target selection: pop a window list at the
    /// mouse so you never have to open the menu-bar menu.
    func selectTargetWindowViaHotkey() {
        let menu = NSMenu()
        let windows = targetWindows()
        if windows.isEmpty {
            let item = NSMenuItem(title: "No windows found", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            let header = NSMenuItem(title: "Select target window:", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())
            for window in windows {
                let item = NSMenuItem(title: window.label,
                                      action: #selector(chooseTarget(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = Box(window)
                if window == AppState.shared.target { item.state = .on }
                menu.addItem(item)
            }
        }
        // With a nil view, the location is interpreted in screen
        // coordinates (bottom-left origin), which is what mouseLocation
        // already gives us.
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc func showHelp() {
        let cfg = AppState.shared.config
        var t = "Fast Debate Paste — Help\n\n"
        t += "Current Hotkeys:\n"
        t += "• Select Target Window: \(cfg.selectTargetWindow)\n"
        t += "• Copy-Paste: \(cfg.performCopyPaste)\n"
        t += "• Copy-Paste (No Line Breaks): \(cfg.performCopyPasteNoLineBreaks)\n"
        t += "• Copy-Paste (No Line Breaks, No Return): \(cfg.performCopyPasteNoLineBreaksNoReturn)\n"
        t += "• Show This Help: \(cfg.showHelp)\n\n"

        t += "What each does:\n"
        t += "• Select Target Window: choose the window evidence gets pasted into (e.g. your CardMirror speech doc).\n"
        t += "• Copy-Paste: copy from the front app, process equation-omissions, switch to the target, and insert as a new paragraph.\n"
        t += "• No Line Breaks: same, but collapses line breaks into spaces.\n"
        t += "• No Line Breaks, No Return: same as above but inserts inline (no new paragraph, prepends a space).\n\n"

        t += "Delivery: when CardMirror is running, text is inserted natively "
        t += "through its integration bridge. Otherwise it falls back to "
        t += "pressing Return + F2 (CardMirror's Paste Plain Text) in the "
        t += "target window.\n\n"

        t += "To change hotkeys or settings, use \"Edit Config…\" in the menu, "
        t += "edit config.json, then \"Reload Config\". Hotkey format: cmd, shift, "
        t += "opt, ctrl joined with +, e.g. cmd+shift+c, f10, ctrl+0."

        let alert = NSAlert()
        alert.messageText = "Fast Debate Paste"
        alert.informativeText = t
        alert.alertStyle = .informational
        // Bring the alert to the front since we're an accessory app.
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func editConfig() {
        // Config.load() in AppState already created the file on first
        // launch; make sure it's on disk, then open it.
        if !FileManager.default.fileExists(atPath: Config.fileURL.path) {
            AppState.shared.config.save()
        }
        NSWorkspace.shared.open(Config.fileURL)
    }

    @objc private func reloadConfig() {
        AppState.shared.config = Config.load()
        registerHotkeys()
        Alerts.info("Config reloaded. Hotkeys re-registered.")
    }

    @objc private func toggleLaunchAtLogin() {
        AppState.shared.config.launchAtLogin.toggle()
        AppState.shared.config.save()
        applyLoginItemSetting()
    }

    /// Register/unregister the app as a login item to match the saved
    /// preference, via SMAppService (macOS 13+).
    private func applyLoginItemSetting() {
        let service = SMAppService.mainApp
        do {
            if AppState.shared.config.launchAtLogin {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled { try service.unregister() }
            }
        } catch {
            Alerts.info("Couldn't update Launch at Login: \(error.localizedDescription)")
        }
    }

    @objc private func openAccessibilitySettings() {
        if AXIsProcessTrusted() {
            Alerts.info("Accessibility is already granted — you're all set.")
            return
        }
        promptForAccessibilityIfNeeded()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Hotkeys & permissions

    private func registerHotkeys() {
        HotKeyManager.shared.unregisterAll()
        let cfg = AppState.shared.config
        let hk = HotKeyManager.shared
        hk.register(cfg.selectTargetWindow) { [weak self] in self?.selectTargetWindowViaHotkey() }
        hk.register(cfg.performCopyPaste) { PasteActions.shared.performCopyPaste() }
        hk.register(cfg.performCopyPasteNoLineBreaks) { PasteActions.shared.performCopyPasteNoLineBreaks() }
        hk.register(cfg.performCopyPasteNoLineBreaksNoReturn) { PasteActions.shared.performCopyPasteNoLineBreaksNoReturn() }
        hk.register(cfg.showHelp) { [weak self] in self?.showHelp() }
    }

    @discardableResult
    private func promptForAccessibilityIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// If we started without Accessibility trust, poll for it and relaunch
    /// once it's granted. macOS only activates the event-posting privilege
    /// on a fresh launch, so without this the user would grant permission,
    /// see "granted", and still get "Failed to copy" until they manually
    /// quit and reopen the app.
    private func startAccessibilityWatchIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        accessibilityWatchTimer = Timer.scheduledTimer(withTimeInterval: 1.0,
                                                       repeats: true) { [weak self] _ in
            guard let self, AXIsProcessTrusted() else { return }
            self.accessibilityWatchTimer?.invalidate()
            self.accessibilityWatchTimer = nil
            self.relaunchForAccessibility()
        }
    }

    private func relaunchForAccessibility() {
        guard !didRelaunchForAccessibility else { return }
        didRelaunchForAccessibility = true
        NSApp.activate(ignoringOtherApps: true)
        Alerts.info("Accessibility granted. Fast Debate Paste needs to restart "
            + "once to finish turning it on — click OK and it will reopen "
            + "automatically.")
        // Detached: re-open the bundle after this instance has exited.
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
