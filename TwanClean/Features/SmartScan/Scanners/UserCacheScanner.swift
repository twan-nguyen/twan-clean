import Foundation

struct UserCacheScanner: CategoryScanner {
    let category = CleanupCategoryID.userCache

    /// Cache folders another category reports in more detail.
    static let claimedCacheNames: Set<String> = [
        "homebrew", "yarn", "com.apple.dt.xcode", "ollama", "com.electron.ollama",
    ]

    func scan(_ context: ScanContext) async throws -> CategoryResult {
        var builder = CategoryResultBuilder(category, context: context)
        // Cache folders are discovered from disk rather than a fixed list, so
        // every app on this Mac shows up.
        try builder.addChildren(of: context.homeURL("Library/Caches"), purpose: .regenerableCache) { url in
            !Self.claimedCacheNames.contains(url.lastPathComponent.lowercased())
        }
        try builder.addChildren(of: context.homeURL(".cache"), purpose: .regenerableCache)
        return builder.finish()
    }
}
