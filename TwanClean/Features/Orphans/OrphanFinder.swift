import Foundation

/// A file left by an app that is no longer installed.
struct OrphanItem: Identifiable, Hashable, Sendable {
    let url: URL
    let identity: FileIdentity
    let bytes: Int64
    let isDirectory: Bool
    let lastModified: Date?
    let requiresAdministrator: Bool

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    /// The folder it was found in, used to group the list.
    var location: URL { url.deletingLastPathComponent() }

    var removalRequest: RemovalRequest {
        RemovalRequest(url: url, purpose: .orphan, identity: identity, bytes: bytes)
    }
}

/// Finds caches and logs whose app is gone. Only folders macOS and apps
/// recreate are searched, so even a wrong guess costs nothing but a rebuild,
/// and everything removed goes to the Trash.
struct OrphanFinder: Sendable {
    let policy: PathPolicy
    let protected: ProtectedLocations?
    /// The folders searched; by default exactly those the orphan removal
    /// policy allows.
    let searchFolders: [URL]

    init(policy: PathPolicy = PathPolicy(), protected: ProtectedLocations? = nil, searchFolders: [URL]? = nil) {
        self.policy = policy
        self.protected = protected
        self.searchFolders = searchFolders
            ?? policy.rules.allowedTrees(for: .orphan).map { URL(fileURLWithPath: $0) }
    }

    /// - Parameters:
    ///   - installed: every installed app; the list must be complete, or the
    ///     files of a missing app would be reported as orphaned.
    ///   - runningBundleIDs: apps running now, which count as installed.
    func find(installed: [InstalledApp], runningBundleIDs: Set<String>, ignored: Set<String>) throws -> [OrphanItem] {
        let matchers = installed.map { AppMatcher(app: $0, sensitivity: .enhanced) }
        let knownIdentifiers = (installed.map(\.bundleIdentifier) + runningBundleIDs).map(\.normalizedForMatching)

        var items: [OrphanItem] = []
        for folder in searchFolders where protected?.contains(folder) != true {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { continue }
            for name in names {
                try Task.checkCancellation()
                let url = folder.appendingPathComponent(name)
                guard !ignored.contains(url.path), !OrphanSkipList.contains(name),
                      !Self.belongsToKnownApp(name, matchers: matchers, knownIdentifiers: knownIdentifiers),
                      case .allowed(let canonical) = policy.evaluate(url, purpose: .orphan),
                      let identity = FileIdentity.of(canonical) else { continue }
                let size = try AllocatedSizeCalculator().measure(canonical)
                guard size.bytes > 0 else { continue }
                items.append(OrphanItem(url: canonical, identity: identity, bytes: size.bytes,
                                        isDirectory: CategoryResultBuilder.isDirectory(canonical),
                                        lastModified: size.latestModification,
                                        requiresAdministrator: RemovalService.needsAdministrator(canonical)))
            }
        }
        return items.sorted { $0.bytes > $1.bytes }
    }

    /// True when the name points at an installed or running app, either
    /// because it contains the app's name or identifier, or because it is
    /// part of an identifier, as "Google" is part of "com.google.Chrome".
    static func belongsToKnownApp(_ name: String, matchers: [AppMatcher], knownIdentifiers: [String]) -> Bool {
        if matchers.contains(where: { $0.match(name) != nil }) { return true }
        let normalized = (name as NSString).deletingPathExtension.normalizedForMatching
        guard normalized.count >= 4 else { return true }
        return knownIdentifiers.contains { $0.contains(normalized) || normalized.contains($0) }
    }
}
