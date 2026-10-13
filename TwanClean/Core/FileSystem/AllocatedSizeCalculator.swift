import Foundation

/// Remembers hard-linked files already counted during one scan, so a file
/// reachable through several links is counted once across every category.
final class SizingSession: @unchecked Sendable {
    private let lock = NSLock()
    private var counted = Set<FileIdentity>()

    /// True the first time `identity` is claimed in this session.
    func claim(_ identity: FileIdentity) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return counted.insert(identity).inserted
    }
}

struct SizeMeasurement: Equatable, Sendable {
    /// Space the items occupy, a hard-linked file counted once.
    var bytes: Int64 = 0
    /// The part of `bytes` held by files that have other hard links outside
    /// the measured items (a pnpm store shares its files with project
    /// folders, say). Removing the items leaves those files on disk.
    var sharedBytes: Int64 = 0
    var fileCount = 0
    /// Folders that could not be listed and items that could not be examined,
    /// so `bytes` is a lower bound when > 0.
    var unreadableEntries = 0
    /// Newest modification date of any file inside.
    var latestModification: Date?

    /// What removing the items frees: `bytes` without the shared files. Use
    /// this, not `bytes`, for any "space to reclaim" figure.
    var reclaimableBytes: Int64 { bytes - sharedBytes }
}

/// Measures the space items really occupy on disk: allocated blocks rather
/// than logical length, hidden files included, symlinks not followed, and
/// hard links counted once per `SizingSession`.
struct AllocatedSizeCalculator: Sendable {
    let session: SizingSession

    init(session: SizingSession = SizingSession()) {
        self.session = session
    }

    func measure(_ url: URL) throws -> SizeMeasurement {
        var result = SizeMeasurement()
        // Multi-link files: how many of their links were met inside this
        // measurement, how many exist, and the bytes counted for them.
        var linked: [FileIdentity: (met: Int, total: Int, bytes: Int64)] = [:]
        try FileTreeWalker.walk(url) { entry in
            switch entry.kind {
            case .file, .symlink:
                if entry.linkCount > 1, let identity = entry.identity {
                    let firstClaim = session.claim(identity)
                    var link = linked[identity] ?? (met: 0, total: entry.linkCount,
                                                    bytes: firstClaim ? entry.allocatedBytes : 0)
                    link.met += 1
                    linked[identity] = link
                    if !firstClaim { return .continue }
                }
                result.bytes += entry.allocatedBytes
                result.fileCount += 1
                if let date = entry.modificationDate, date > (result.latestModification ?? .distantPast) {
                    result.latestModification = date
                }
            case .unreadableDirectory, .unreadable:
                result.unreadableEntries += 1
            case .directory, .directoryEnd:
                break
            }
            return .continue
        }
        result.sharedBytes = linked.values.reduce(0) { $0 + ($1.met < $1.total ? $1.bytes : 0) }
        return result
    }
}
