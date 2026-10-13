import Foundation

/// One item a feature wants removed, with the identity it had when scanned.
struct RemovalRequest: Hashable, Sendable {
    let url: URL
    let purpose: RemovalPurpose
    let identity: FileIdentity
    /// Size the feature reported, used to total what was freed.
    let bytes: Int64

    init(url: URL, purpose: RemovalPurpose, identity: FileIdentity, bytes: Int64) {
        self.url = url
        self.purpose = purpose
        self.identity = identity
        self.bytes = bytes
    }
}

struct RemovalReport: Sendable {
    struct Failure: Sendable {
        let request: RemovalRequest
        let message: String
    }

    /// Removed, or moved to the Trash.
    var removed: [RemovalRequest] = []
    /// Where trashed items now are, when macOS reported it.
    var trashedLocations: [URL] = []
    /// Already gone before removal ran; nothing left to free.
    var alreadyGone: [RemovalRequest] = []
    /// Blocked by file permissions; may succeed with administrator rights.
    var needsAdministrator: [RemovalRequest] = []
    var refused: [(request: RemovalRequest, reason: RefusalReason)] = []
    var failed: [Failure] = []

    var freedBytes: Int64 { removed.reduce(0) { $0 + $1.bytes } }

    mutating func merge(_ other: RemovalReport) {
        removed += other.removed
        trashedLocations += other.trashedLocations
        alreadyGone += other.alreadyGone
        needsAdministrator += other.needsAdministrator
        refused += other.refused
        failed += other.failed
    }
}

/// How far a removal has got: `completed` of `total` requests are settled, and
/// `url` is the one being worked on, or the last one settled.
struct RemovalStep: Sendable, Equatable {
    let completed: Int
    let total: Int
    let url: URL
}

/// Called from whichever thread does the removal, so it must be cheap and
/// must not touch interface state directly.
typealias RemovalProgressHandler = @Sendable (RemovalStep) -> Void

/// The only place that removes files. Every request is checked against
/// `PathPolicy` and against its scanned identity immediately before removal,
/// and its purpose decides whether it is deleted or moved to the Trash.
struct RemovalService: Sendable {
    /// Moves an item to the Trash and returns where it went.
    typealias Trash = @Sendable (URL) throws -> URL?

    let policy: PathPolicy
    let trash: Trash

    init(policy: PathPolicy = PathPolicy(), trash: @escaping Trash = RemovalService.moveToTrash) {
        self.policy = policy
        self.trash = trash
    }

    /// Trashing from this process, not a helper, is what makes macOS list
    /// Twan Clean under Full Disk Access when it is refused.
    static let moveToTrash: Trash = { url in
        var location: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &location)
        return location as URL?
    }

    /// - Parameter progress: told before each request is handled, and once more
    ///   when the last one is settled. Every request counts, whether it is
    ///   removed, refused or already gone.
    func remove(_ requests: [RemovalRequest], progress: RemovalProgressHandler? = nil) async -> RemovalReport {
        var report = RemovalReport()
        for (index, request) in requests.enumerated() {
            if Task.isCancelled { return report }
            progress?(RemovalStep(completed: index, total: requests.count, url: request.url))
            remove(request, into: &report)
        }
        if let last = requests.last {
            progress?(RemovalStep(completed: requests.count, total: requests.count, url: last.url))
        }
        return report
    }

    /// Re-checks a request right before acting on it. Returns the canonical URL
    /// to act on, or nil after recording why the request cannot go ahead.
    func validate(_ request: RemovalRequest, into report: inout RemovalReport) -> URL? {
        switch policy.evaluate(request.url, purpose: request.purpose) {
        case .refused(let reason):
            report.refused.append((request, reason))
            return nil
        case .allowed(let url):
            switch FileIdentity.lookup(url) {
            case .missing:
                report.alreadyGone.append(request)
                return nil
            case .unexaminable:
                report.needsAdministrator.append(request)
                return nil
            case .found(let current) where current != request.identity:
                report.refused.append((request, .changedSinceScan))
                return nil
            case .found:
                if FileIdentity.isMountPoint(url) {
                    report.refused.append((request, .mountPoint))
                    return nil
                }
                return url
            }
        }
    }

    private func remove(_ request: RemovalRequest, into report: inout RemovalReport) {
        guard let url = validate(request, into: &report) else { return }
        do {
            switch request.purpose.mode {
            case .delete:
                try DescriptorRemover.remove(url, expecting: request.identity)
            case .trash:
                if let location = try trash(url) { report.trashedLocations.append(location) }
            }
            report.removed.append(request)
        } catch DescriptorRemover.Failure.mountPoint {
            // Administrator rights would not get past the mount either.
            report.refused.append((request, .mountPoint))
        } catch DescriptorRemover.Failure.changed {
            report.refused.append((request, .changedSinceScan))
        } catch where Self.isPermissionError(error) {
            report.needsAdministrator.append(request)
        } catch where FileIdentity.lookup(url) == .missing {
            // Removed by someone else in the meantime.
            report.alreadyGone.append(request)
        } catch {
            report.failed.append(.init(request: request, message: error.localizedDescription))
        }
    }

    /// Whether removing the item will need the administrator prompt: its
    /// folder is not writable, a sticky folder (like /tmp) protects another
    /// user's item, or a folder owned by someone else will have contents this
    /// user cannot remove.
    static func needsAdministrator(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent().path
        guard access(parent, W_OK) == 0 else { return true }
        var parentStatus = stat()
        var itemStatus = stat()
        guard lstat(parent, &parentStatus) == 0, lstat(url.path, &itemStatus) == 0 else { return true }
        let ownedByOther = itemStatus.st_uid != getuid()
        let isDirectory = (itemStatus.st_mode & S_IFMT) == S_IFDIR
        let parentIsSticky = (parentStatus.st_mode & S_ISVTX) != 0
        return ownedByOther && (parentIsSticky || isDirectory)
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(nsError.code) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isPermissionError(underlying)
        }
        return nsError.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(nsError.code)
    }
}
