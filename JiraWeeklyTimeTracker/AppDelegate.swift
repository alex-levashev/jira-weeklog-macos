import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    
    var sessionManager = SessionManager()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        sessionManager.tryAutoLogin()
        
        let contentView = RootView()
            .environmentObject(sessionManager)
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 300)
        popover.behavior = .transient          // ① let AppKit auto-close it
        popover.delegate  = self               // ② we’ll listen for close events
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "clock",
                                   accessibilityDescription: "Worklog")
            button.action = #selector(togglePopover(_:))
        }
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Make *this* app active so the popover can become key.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds,
                         of: button,
                         preferredEdge: .minY)
        }
    }
    
    // Extra safety-net: close when the app resigns active status
    func applicationWillResignActive(_ notification: Notification) {
        if popover.isShown {
            popover.performClose(nil)
        }
    }
}
