import Foundation

struct HomebrewCacheScanner: CategoryScanner {
    let category = CleanupCategoryID.brew

    func scan(_ context: ScanContext) async throws -> CategoryResult {
        var builder = CategoryResultBuilder(category, context: context)
        var folders = [context.homeURL("Library/Caches/Homebrew")]
        // A custom HOMEBREW_CACHE is honoured only where the policy allows
        // cache removal; anything else is skipped by the builder.
        if let reported = await context.commands.output(of: "brew", ["--cache"]), reported.hasPrefix("/") {
            folders.append(URL(fileURLWithPath: reported, isDirectory: true))
        }
        for folder in folders {
            try builder.addChildren(of: folder, purpose: .regenerableCache)
        }
        return builder.finish()
    }
}
