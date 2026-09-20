import AppKit
import SwiftUI

/// Static menu-bar icon: no angle updates, title timer, or background UI work.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()

    init(controller: LidController, preferences: Preferences) {
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "Mac Duo")
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        popover.behavior = .transient
        let hosting = NSHostingController(rootView: SettingsView(preferences: preferences, controller: controller, onQuit: { NSApp.terminate(nil) }))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
    }
    func showSettings() {
        guard let button = statusItem.button else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown { popover.performClose(sender) }
        else { showSettings() }
    }
}
