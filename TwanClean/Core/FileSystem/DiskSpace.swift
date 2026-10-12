import Foundation

/// Capacity of the startup volume.
struct DiskSpace: Equatable, Sendable {
    let totalBytes: Int64
    /// Free right now.
    let availableBytes: Int64
    /// Space macOS can free on its own when needed (APFS purgeable data such
    /// as iCloud copies and local snapshots). Shown only: no app can reclaim
    /// it on macOS's behalf.
    let purgeableBytes: Int64

    var usedBytes: Int64 { max(0, totalBytes - availableBytes) }

    static func current(for volume: URL = URL(fileURLWithPath: "/")) -> DiskSpace? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let values = try? volume.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacity else { return nil }
        let important = values.volumeAvailableCapacityForImportantUsage ?? Int64(available)
        return DiskSpace(totalBytes: Int64(total), availableBytes: Int64(available),
                         purgeableBytes: max(0, important - Int64(available)))
    }
}
