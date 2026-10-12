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

/// The only place that removes files. Every request is checked against
/// `PathPolicy` and against its scanned identity immediately before removal,
/// and its purpose decides whether it is deleted or moved to the Trash.
struct RemovalService: Sendable {
    let policy: PathPolicy

    init(policy: PathPolicy = PathPolicy()) {
        self.policy = policy
    }

    func remove(_ requests: [RemovalRequest]) async -> RemovalReport {
        var report = RemovalReport()
        for request in requests {
            if Task.isCancelled { break }
            remove(request, into: &report)
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
            guard let current = FileIdentity.of(url) else {
                report.alreadyGone.append(request)
                return nil
            }
            guard current == request.identity else {
                report.refused.append((request, .changedSinceScan))
                return nil
            }
            return url
        }
    }

    private func remove(_ request: RemovalRequest, into report: inout RemovalReport) {
        guard let url = validate(request, into: &report) else { return }
        do {
            switch request.purpose.mode {
            case .delete:
                try FileManager.default.removeItem(at: url)
            case .trash:
                // Trashing from this process, not a helper, is what makes macOS
                // list Twan Clean under Full Disk Access when it is refused.
                var location: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &location)
                if let location { report.trashedLocations.append(location as URL) }
            }
            report.removed.append(request)
        } catch where Self.isPermissionError(error) {
            report.needsAdministrator.append(request)
        } catch {
            report.failed.append(.init(request: request, message: error.localizedDescription))
        }
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
