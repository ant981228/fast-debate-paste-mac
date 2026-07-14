import AppKit

// Manual app bootstrap (no @main / storyboard): create the shared
// application, attach our delegate, and run. Activation policy is set
// to .accessory in the delegate so this lives only in the menu bar.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
