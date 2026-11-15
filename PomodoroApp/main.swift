#if canImport(PomodoroKit)
import PomodoroKit
#endif
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
