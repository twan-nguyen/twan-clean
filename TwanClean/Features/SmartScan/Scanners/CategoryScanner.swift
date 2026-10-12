import Foundation

/// Finds the removable items of one Smart Scan category.
protocol CategoryScanner: Sendable {
    var category: CleanupCategoryID { get }
    func scan(_ context: ScanContext) async throws -> CategoryResult
}

extension URL {
    /// Modification date of the item itself, without following a symlink.
    var modificationDateWithoutFollowing: Date? {
        var status = stat()
        guard lstat(path, &status) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(status.st_mtimespec.tv_sec))
    }
}
