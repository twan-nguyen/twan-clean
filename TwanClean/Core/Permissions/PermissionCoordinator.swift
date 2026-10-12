import Combine
import Foundation

/// Follows the Full Disk Access switch while the user is in System Settings,
/// so the app can react as soon as it is turned on.
@MainActor
final class PermissionCoordinator: ObservableObject {
    enum State: Equatable {
        case granted
        case notGranted
        /// Granted, but macOS applies it only after Twan Clean restarts.
        case needsRelaunch
    }

    @Published private(set) var state: State = FullDiskAccess.isGranted() ? .granted : .notGranted
    private var pollTask: Task<Void, Never>?

    func refresh() async {
        if FullDiskAccess.isGranted() {
            state = .granted
        } else {
            state = await FullDiskAccess.isGrantedForNewProcesses() ? .needsRelaunch : .notGranted
        }
    }

    /// Checks once a second until access is granted or polling stops.
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                if self?.state != .notGranted { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            self?.pollTask = nil
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
