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
    @objc func uninstallApp(_ pasteboard: NSPasteboard, userData: String?,
                            error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard let app = urls.first(where: { $0.pathExtension.lowercased() == "app" }) else {
            error.pointee = String(localized: "Choose an application to uninstall.") as NSString
            return
        }
        // Only installed apps: not one on a disk image, nor a helper inside
        // another app.
        guard case .allowed = PathPolicy().evaluate(app, purpose: .appBundle), InstalledAppIndex.app(at: app) != nil else {
            error.pointee = String(localized: "Twan Clean can only uninstall apps in the Applications folder.") as NSString
            return
        }
        pendingUninstall = app
        deliverPendingUninstall()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func deliverPendingUninstall() {
        guard let model, let url = pendingUninstall else { return }
        pendingUninstall = nil
        model.uninstaller.selectApp(at: url)
        model.showMainWindow(.uninstaller)
    }
}
