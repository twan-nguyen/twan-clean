import AppKit
import SwiftUI

/// The menu bar icon and its popover. Shown or hidden as the user's setting
/// changes, without a relaunch.
@MainActor
final class MenuBarController: NSObject {
    private let model: AppModel
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var defaultsObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        super.init()
        popover.behavior = .transient
        update()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    private func update() {
        if MenuBarSettings.isShown, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Twan Clean")
            item.button?.target = self
            item.button?.action = #selector(togglePopover(_:))
            statusItem = item
        } else if !MenuBarSettings.isShown, let item = statusItem {
            popover.performClose(nil)
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        // A fresh view each time, so disk space and the last run are current.
        popover.contentViewController = NSHostingController(rootView: MenuBarPanel(appModel: model) { [weak self] in
            self?.popover.performClose(nil)
        })
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
