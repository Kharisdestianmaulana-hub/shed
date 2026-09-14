// Copyright (c) 2026 Kharis Destian Maulana. All rights reserved.
import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup Popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 380)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarPopupView())
        self.popover = popover
        
        // Setup Status Item
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = self.statusItem.button {
            button.image = NSImage(systemSymbolName: "trash.circle.fill", accessibilityDescription: "Shed")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        // Auto-cleanup quarantined items if the user enabled the toggle
        QuarantineManager.shared.autoCleanup()
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = self.statusItem.button {
            if self.popover.isShown {
                self.popover.performClose(sender)
            } else {
                NSApp.activate(ignoringOtherApps: true)
                self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            }
        }
    }
    
    // Aplikasi akan tetap hidup di Menu Bar walau jendela utamanya di-close (X)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false 
    }
}
