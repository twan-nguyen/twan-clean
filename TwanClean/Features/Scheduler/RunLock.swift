import Foundation

/// Keeps the app and the scheduled run from scanning or cleaning at the same
/// time. The lock is an `flock` on a file, released when this object goes
/// away or the process ends.
final class RunLock: @unchecked Sendable {
    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    static var defaultFile: URL {
        ScheduleStore.defaultFolder.appendingPathComponent("scan.lock")
    }

    /// The lock, or nil when someone else holds it.
    static func acquire(at file: URL = RunLock.defaultFile) -> RunLock? {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(file.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return RunLock(descriptor: descriptor)
    }
}
