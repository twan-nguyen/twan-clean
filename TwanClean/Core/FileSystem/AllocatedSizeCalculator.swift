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
    var bytes: Int64 = 0
    var fileCount = 0
    /// Folders that could not be listed and items that could not be examined,
    /// so `bytes` is a lower bound when > 0.
    var unreadableEntries = 0
    /// Newest modification date of any file inside.
    var latestModification: Date?
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
        try FileTreeWalker.walk(url) { entry in
            switch entry.kind {
            case .file, .symlink:
                if entry.linkCount > 1, let identity = entry.identity, !session.claim(identity) {
                    return .continue
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
        return result
    }
}
