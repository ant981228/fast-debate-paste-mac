import AppKit
import ApplicationServices

/// A window the user can target as the paste destination.
struct TargetWindow: Equatable {
    let pid: pid_t
    let appName: String
    let title: String

    /// Label shown in the menu, e.g. "CardMirror — Aff Case.cmir".
    var label: String {
        let t = title.isEmpty ? "(untitled window)" : title
        return "\(appName) — \(t)"
    }
}

/// Lists and activates windows using the Accessibility API. This
/// avoids the Screen Recording permission that CGWindowList-based
/// title reading would require — Accessibility is already needed to
/// synthesize keystrokes.
enum WindowTargeting {
    /// Enumerate the on-screen windows of all regular (Dock-visible)
    /// apps, with their titles. Skips this app itself.
    static func listWindows() -> [TargetWindow] {
        var result: [TargetWindow] = []
        let me = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  app.processIdentifier != me,
                  app.processIdentifier > 0 else { continue }
            let name = app.localizedName ?? "Unknown"
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(axApp,
                                                       kAXWindowsAttribute as CFString,
                                                       &windowsRef)
            guard status == .success,
                  let windows = windowsRef as? [AXUIElement] else { continue }
            for window in windows {
                // Skip minimized windows — they can't be a useful paste
                // target until restored, and they clutter the list.
                if boolAttr(window, kAXMinimizedAttribute) == true { continue }
                let title = stringAttr(window, kAXTitleAttribute) ?? ""
                result.append(TargetWindow(pid: app.processIdentifier,
                                           appName: name,
                                           title: title))
            }
        }
        return result
    }

    /// Bring the target window to the front and wait briefly for the
    /// app to actually become frontmost. Returns false if the app is
    /// gone.
    @discardableResult
    static func activate(_ target: TargetWindow, timeoutMs: Int) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: target.pid) else {
            return false
        }
        // Raise the specific window (best effort) before activating the
        // app, so the right window is frontmost when focus arrives.
        let axApp = AXUIElementCreateApplication(target.pid)
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for window in windows where (stringAttr(window, kAXTitleAttribute) ?? "") == target.title {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                break
            }
        }
        app.activate(options: [.activateIgnoringOtherApps])

        // Poll until this pid is frontmost or we time out.
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid {
                return true
            }
            usleep(20_000)
        }
        return true  // activation issued even if frontmost check lagged
    }

    /// Is the target's app still running?
    static func stillExists(_ target: TargetWindow) -> Bool {
        NSRunningApplication(processIdentifier: target.pid) != nil
    }

    static func frontmostPID() -> pid_t {
        NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
    }

    // MARK: - AX attribute helpers

    private static func stringAttr(_ element: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else {
            return nil
        }
        return ref as? String
    }

    private static func boolAttr(_ element: AXUIElement, _ attr: String) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else {
            return nil
        }
        return (ref as? Bool)
    }
}
