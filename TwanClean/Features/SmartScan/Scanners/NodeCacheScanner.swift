import Foundation

struct NodeCacheScanner: CategoryScanner {
    let category = CleanupCategoryID.node

    func scan(_ context: ScanContext) async throws -> CategoryResult {
        async let npm = context.commands.output(of: "npm", ["config", "get", "cache"])
        async let yarn = context.commands.output(of: "yarn", ["cache", "dir"])
        async let pnpm = context.commands.output(of: "pnpm", ["store", "path"])
        let (npmCache, yarnCache, pnpmStore) = await (npm, yarn, pnpm)

        var builder = CategoryResultBuilder(category, context: context)
        let npmRoot = Self.absoluteURL(npmCache) ?? context.homeURL(".npm")
        for name in ["_cacache", "_npx", "_logs"] {
            try builder.add(npmRoot.appendingPathComponent(name), purpose: .regenerableCache)
        }
        try builder.add(Self.absoluteURL(yarnCache) ?? context.homeURL("Library/Caches/Yarn"), purpose: .regenerableCache)
        if let store = Self.absoluteURL(pnpmStore) {
            try builder.add(store, purpose: .regenerableCache)
        } else {
            try builder.addChildren(of: context.homeURL("Library/pnpm/store"), purpose: .regenerableCache)
        }
        return builder.finish()
    }

    private static func absoluteURL(_ output: String?) -> URL? {
        guard let line = output?.split(separator: "\n").last, line.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: String(line), isDirectory: true)
    }
}
