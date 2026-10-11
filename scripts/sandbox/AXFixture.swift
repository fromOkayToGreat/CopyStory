import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 140), styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.title = "CopyStory synthetic AX fixture"
let field = NSTextField(frame: NSRect(x: 24, y: 50, width: 350, height: 28))
field.stringValue = "Synthetic focus target — no clipboard content"
window.contentView!.addSubview(field)
let menu = NSMenu()
let item = NSMenuItem(); let submenu = NSMenu()
submenu.addItem(withTitle: "Quit fixture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
item.submenu = submenu; menu.addItem(item); app.mainMenu = menu
window.makeKeyAndOrderFront(nil); window.makeFirstResponder(field); app.activate(ignoringOtherApps: true)
app.run()
