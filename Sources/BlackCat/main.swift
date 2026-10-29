import AppKit

MainActor.assumeIsolated { Migration.fromHappytoHelp() }  // avant de lire réglages et tâches

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
