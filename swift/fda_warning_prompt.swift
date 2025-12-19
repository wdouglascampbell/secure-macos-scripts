#!/usr/bin/swift

import Cocoa

// Initialize the app (required for dialogs)
let app = NSApplication.shared
app.setActivationPolicy(.accessory) // Makes it appear as a small accessory app without Dock icon

// Create alert
let alert = NSAlert()
alert.messageText = "Terminal has Full Disk Access"
alert.informativeText = "It is not recommended for Terminal to always have Full Disk Access. Would you like instructions on disabling access?"
alert.icon = NSImage(named: NSImage.cautionName)
alert.alertStyle = .warning
alert.addButton(withTitle: "Yes")
alert.addButton(withTitle: "No")

// Bring alert to front
NSApp.activate(ignoringOtherApps: true)
let response = alert.runModal()

// Exit code: 0 for Yes, 1 for No
switch response {
case .alertFirstButtonReturn:
    exit(0)
default:
    exit(1)
}

