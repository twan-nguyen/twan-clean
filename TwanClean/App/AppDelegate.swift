import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set once the main window appears. Requests that arrive earlier, such
    /// as a Finder service that launched the app, wait until then.
    var model: AppModel? {
        didSet {
            deliverPendingUninstall()
            if let model, menuBar == nil { menuBar = MenuBarController(model: model) }
        }
    }

    private var pendingUninstall: URL?
    private var menuBar: MenuBarController?

    /// Before any window exists, so it never flashes in the other appearance.
    func applicationWillFinishLaunching(_ notification: Notification) {
        let saved = UserDefaults.standard.string(forKey: AppearanceMode.storageKey)
        (saved.flatMap(AppearanceMode.init(rawValue:)) ?? .system).apply()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    /// With the menu bar icon shown, closing the window keeps the app there.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !MenuBarSettings.isShown
    }

    /// Finder › Services › Uninstall with Twan Clean, declared in Info.plist.
    /// The first app in the selection that can be uninstalled is opened; when
    /// none can, the reason for the first is reported back to Finder.
    @objc func uninstallApp(_ pasteboard: NSPasteboard, userData: String?,
                            error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if let model {
            switch model.uninstaller.selectApp(from: urls) {
            case .selected:
                model.showMainWindow(.uninstaller)
                NSApp.activate(ignoringOtherApps: true)
            case .rejected(let rejection):
                error.pointee = rejection.message as NSString
            }
            return
        }
        // Launched by the service: the window does not exist yet, so the app
        // waits until it does.
        switch FinderServiceRequest.app(from: urls) {
        case .success(let app):
            pendingUninstall = app.url
            NSApp.activate(ignoringOtherApps: true)
        case .failure(let rejection):
            error.pointee = rejection.message as NSString
        }
    }

    private func deliverPendingUninstall() {
        guard let model, let url = pendingUninstall else { return }
        pendingUninstall = nil
        model.uninstaller.selectApp(at: url)
        model.showMainWindow(.uninstaller)
    }
}
