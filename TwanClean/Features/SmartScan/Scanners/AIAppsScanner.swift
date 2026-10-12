import Foundation

struct AIAppsScanner: CategoryScanner {
    let category = CleanupCategoryID.aiApps

    func scan(_ context: ScanContext) async throws -> CategoryResult {
        var builder = CategoryResultBuilder(category, context: context)
        try builder.addChildren(of: context.homeURL(".ollama/logs"), purpose: .regenerableCache)
        try builder.addChildren(of: context.homeURL(".lmstudio/server-logs"), purpose: .regenerableCache)
        for path in [
            "Library/Caches/ollama",
            "Library/Caches/com.electron.ollama",
            "Library/WebKit/com.electron.ollama",
            "Library/Saved Application State/com.electron.ollama.savedState",
        ] {
            try builder.add(context.homeURL(path), purpose: .regenerableCache)
        }
        // Chat history is the user's own data: offered, never preselected, and
        // only ever moved to the Trash.
        for path in [".ollama/history", ".lmstudio/conversations"] {
            try builder.add(context.homeURL(path), purpose: .userFile, selected: false, notes: [.personalData])
        }
        return builder.finish()
    }
}
