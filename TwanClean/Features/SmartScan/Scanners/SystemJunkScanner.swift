import Foundation

struct SystemJunkScanner: CategoryScanner {
    let category = CleanupCategoryID.systemJunk

    /// Temporary items younger than this may belong to something running.
    static let temporaryItemMinimumAge: TimeInterval = 3 * 24 * 60 * 60

    func scan(_ context: ScanContext) async throws -> CategoryResult {
        var builder = CategoryResultBuilder(category, context: context)
        try builder.addChildren(of: context.homeURL("Library/Logs"), purpose: .regenerableCache)
        for path in ["/Library/Caches", "/Library/Logs", "/private/var/log"] {
            try builder.addChildren(of: URL(fileURLWithPath: path), purpose: .regenerableCache)
        }
        let cutoff = context.now.addingTimeInterval(-Self.temporaryItemMinimumAge)
        for path in ["/private/var/tmp", "/private/tmp"] {
            try builder.addChildren(of: URL(fileURLWithPath: path), purpose: .regenerableCache) { url in
                (url.modificationDateWithoutFollowing ?? context.now) < cutoff
            }
        }
        return builder.finish()
    }
}
