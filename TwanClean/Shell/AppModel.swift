import SwiftUI

/// Owns each feature's state for the life of the app, so switching screens in
/// the sidebar never throws away a scan.
@MainActor
final class AppModel: ObservableObject {
    let smartScan = SmartScanViewModel()
    let spaceLens = SpaceLensViewModel()
    let uninstaller = UninstallerViewModel()
    /// A screen another part of the app asks the window to show.
    @Published var route: SidebarItem?
}
