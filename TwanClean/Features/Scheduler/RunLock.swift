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

    enum Attempt {
        case acquired(RunLock)
        /// Someone else holds the lock.
        case busy
        /// The lock file cannot be created or locked, so nobody can say
        /// whether a scan is running.
        case unavailable(reason: String)
    }

    static func attempt(at file: URL = RunLock.defaultFile) -> Attempt {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return .unavailable(reason: error.localizedDescription)
        }
        let descriptor = open(file.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { return .unavailable(reason: String(cString: strerror(errno))) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            return code == EWOULDBLOCK ? .busy : .unavailable(reason: String(cString: strerror(code)))
        }
        return .acquired(RunLock(descriptor: descriptor))
    }

    /// The lock, or nil when someone else holds it or it cannot be taken.
    static func acquire(at file: URL = RunLock.defaultFile) -> RunLock? {
        if case .acquired(let lock) = attempt(at: file) { return lock }
        return nil
    }
}
