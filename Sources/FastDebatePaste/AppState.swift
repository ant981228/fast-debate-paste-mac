import AppKit

/// Shared app state: the loaded config and the currently selected
/// target window. Mutated on the main thread (menu / hotkey handlers);
/// snapshotted before any background work.
final class AppState {
    static let shared = AppState()
    var config = Config.load()
    var target: TargetWindow?
    private init() {}
}

/// Small wrappers around NSAlert so action code can surface errors
/// without importing AppKit everywhere. Always shown on the main thread.
enum Alerts {
    static func info(_ message: String, title: String = "Fast Debate Paste") {
        onMain {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.runModal()
        }
    }

    private static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() }
        else { DispatchQueue.main.async(execute: work) }
    }
}
