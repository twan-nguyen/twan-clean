import SwiftUI

/// Owns each feature's state for the life of the app, so switching screens in
/// the sidebar never throws away a scan.
@MainActor
final class AppModel: ObservableObject {
    let smartScan = SmartScanViewModel()
}
