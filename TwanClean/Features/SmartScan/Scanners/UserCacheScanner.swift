import Foundation

struct UserCacheScanner: CategoryScanner {
    let category = CleanupCategoryID.userCache

    /// Cache folders another category reports in more detail.
    static let claimedCacheNames: Set<String> = [
        "homebrew", "yarn", "com.apple.dt.xcode", "ollama", "com.electron.ollama",
    ]

    /// Folders of ~/Library/Caches that hold more than a cache, by their usual
    /// spelling. They are listed so the space is visible, but never preselected.
    static let keptLibraryCacheNames: [String: CleanableItem.Note] = [
        // The IDEs' system folders: Local History, which exists nowhere else.
        "JetBrains": .personalData,
        // Poetry keeps its virtual environments here, not only downloads.
        "pypoetry": .mayBeNeeded,
        // Songs downloaded for offline listening.
        "com.spotify.client": .mayBeNeeded,
    ]

    /// Android Studio is an IDE of the JetBrains family; its system folder
    /// sits next to Chrome's cache in ~/Library/Caches/Google.
    static let sharedVendorFolder = "Google"
    static let keptSharedVendorPrefix = "androidstudio"

    /// Folders of ~/.cache known to hold only what their tool downloads or
    /// builds again. Any other folder there is only listed: it may be a tool's
    /// data, such as downloaded models or saved sessions.
    static let regenerableDotCacheNames: Set<String> = [
        "pip", "node-gyp", "yarn", "go-build", "typescript", "prisma", "puppeteer", "ms-playwright",
        "selenium", "deno", "uv", "ruff", "mypy", "pre-commit", "electron", "electron-builder",
        "vscode-cpptools", "matplotlib", "fontconfig", "thumbnails",
    ]

    /// Folders of ~/.cache that mix cache with the user's own data, such as
    /// Hugging Face's login token next to its models or LM Studio's chats.
    static let personalDotCacheNames: Set<String> = ["huggingface", "lm-studio"]

    func scan(_ context: ScanContext) async throws -> CategoryResult {
        var builder = CategoryResultBuilder(category, context: context)
        let caches = context.homeURL("Library/Caches")
        let handledSeparately = Set(Self.keptLibraryCacheNames.keys.map { $0.lowercased() })
            .union([Self.sharedVendorFolder.lowercased()])

        // Cache folders are discovered from disk rather than a fixed list, so
        // every app on this Mac shows up.
        try builder.addChildren(of: caches, purpose: .regenerableCache) { url in
            let name = url.lastPathComponent.lowercased()
            return !Self.claimedCacheNames.contains(name) && !handledSeparately.contains(name)
        }
        for (name, note) in Self.keptLibraryCacheNames.sorted(by: { $0.key < $1.key }) {
            try builder.add(caches.appendingPathComponent(name), purpose: .regenerableCache, selected: false,
                            notes: [note], owners: [name])
        }
        let shared = caches.appendingPathComponent(Self.sharedVendorFolder)
        try builder.addChildren(of: shared, purpose: .regenerableCache, owners: [Self.sharedVendorFolder]) { url in
            !url.lastPathComponent.lowercased().hasPrefix(Self.keptSharedVendorPrefix)
        }
        try builder.addChildren(of: shared, purpose: .regenerableCache, selected: false, notes: [.personalData],
                                owners: [Self.sharedVendorFolder]) { url in
            url.lastPathComponent.lowercased().hasPrefix(Self.keptSharedVendorPrefix)
        }

        // ~/.cache has no convention for what a folder holds: only the ones
        // known to be regenerable are preselected. The rest go to the Trash
        // if the user picks them.
        let dotCache = context.homeURL(".cache")
        try builder.addChildren(of: dotCache, purpose: .regenerableCache) { url in
            Self.regenerableDotCacheNames.contains(url.lastPathComponent.lowercased())
        }
        try builder.addChildren(of: dotCache, purpose: .userFile, selected: false, notes: [.mayBeNeeded]) { url in
            let name = url.lastPathComponent.lowercased()
            return !Self.regenerableDotCacheNames.contains(name) && !Self.personalDotCacheNames.contains(name)
        }
        for name in Self.personalDotCacheNames.sorted() {
            try builder.add(dotCache.appendingPathComponent(name), purpose: .userFile, selected: false,
                            notes: [.personalData])
        }
        return builder.finish()
    }
}
