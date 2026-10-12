import Foundation

struct UserCacheScanner: CategoryScanner {
    let category = CleanupCategoryID.userCache

    /// Cache folders another category reports in more detail.
    static let claimedCacheNames: Set<String> = [
        "homebrew", "yarn", "com.apple.dt.xcode", "ollama", "com.electron.ollama",
    ]

    static let personalCacheNames: Set<String> = ["huggingface"]

    func scan(_ context: ScanContext) async throws -> CategoryResult {
        var builder = CategoryResultBuilder(category, context: context)
        // Cache folders are discovered from disk rather than a fixed list, so
        // every app on this Mac shows up.
        try builder.addChildren(of: context.homeURL("Library/Caches"), purpose: .regenerableCache) { url in
            !Self.claimedCacheNames.contains(url.lastPathComponent.lowercased())
        }
        // Some tools keep more than cache in ~/.cache, such as Hugging Face's
        // login token next to its downloaded models; those are only listed.
        try builder.addChildren(of: context.homeURL(".cache"), purpose: .regenerableCache) { url in
            !Self.personalCacheNames.contains(url.lastPathComponent.lowercased())
        }
        for name in Self.personalCacheNames {
            try builder.add(context.homeURL(".cache/\(name)"), purpose: .regenerableCache, selected: false, notes: [.personalData])
        }
        return builder.finish()
    }
}
