import SwiftUI

/// Owns each feature's state for the life of the app, so switching screens in
/// the sidebar never throws away a scan.
@MainActor
final class AppModel: ObservableObject {
    let smartScan = SmartScanViewModel()
    let spaceLens = SpaceLensViewModel()
    let uninstaller = UninstallerViewModel()
    let orphans = OrphansViewModel()
    /// A screen another part of the app asks the window to show.
    @Published var route: SidebarItem?
    /// Brings back the main window, set once it first appears.
    var openMainWindow: () -> Void = {}

    func showMainWindow(_ item: SidebarItem? = nil) {
        openMainWindow()
        NSApp.activate(ignoringOtherApps: true)
        if let item { route = item }
    }
}
