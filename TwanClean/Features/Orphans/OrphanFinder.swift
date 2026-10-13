import AppKit

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
    enum ScanError: LocalizedError {
        /// Nothing installed was found, or a folder of apps could not be read:
        /// the files of an app that is there would be reported as orphaned.
        case incompleteAppList

        var errorDescription: String? {
            String(localized: "Twan Clean could not read the list of installed apps, so it cannot tell which files are left over.")
        }
    }

    let policy: PathPolicy
    let protected: ProtectedLocations?
    /// The folders searched; by default exactly those the orphan removal
    /// policy allows.
    let searchFolders: [URL]
    /// Folders shared with the system, where only names in the form of a
    /// bundle identifier can be an app's: macOS keeps its own logs there under
    /// plain names such as WindowServer.
    let bundleIdentifierOnlyFolders: [String]
    /// Whether LaunchServices has an app with this bundle identifier.
    let isRegistered: @Sendable (String) -> Bool

    init(policy: PathPolicy = PathPolicy(), protected: ProtectedLocations? = nil, searchFolders: [URL]? = nil,
         bundleIdentifierOnlyFolders: [String] = ["/Library/Logs"],
         isRegistered: @escaping @Sendable (String) -> Bool = OrphanFinder.registeredWithLaunchServices) {
        self.policy = policy
        self.protected = protected
        self.searchFolders = searchFolders
            ?? policy.rules.allowedTrees(for: .orphan).map { URL(fileURLWithPath: $0) }
        self.bundleIdentifierOnlyFolders = bundleIdentifierOnlyFolders
        self.isRegistered = isRegistered
    }

    /// An app LaunchServices has registered that still exists and is not in
    /// the Trash.
    @Sendable
    static func registeredWithLaunchServices(_ bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleIdentifier).contains {
            !$0.path.contains("/.Trash/") && FileIdentity.of($0) != nil
        }
    }

    /// What is installed, in the forms a file name is compared with.
    struct KnownApps: Sendable {
        let matchers: [AppMatcher]
        /// Bundle identifiers and other identifiers, normalized.
        let identifiers: [String]
        /// App names, normalized, for files named after the app and then
        /// something else (a date, a number).
        let names: [String]

        init(installed: [InstalledApp], runningBundleIDs: Set<String>, extraIdentifiers: Set<String>) {
            matchers = installed.map { AppMatcher(app: $0, sensitivity: .enhanced) }
            identifiers = (installed.map(\.bundleIdentifier) + runningBundleIDs + extraIdentifiers)
                .map(\.normalizedForMatching)
            names = installed.flatMap { [$0.name, $0.fileStem] }.map(\.normalizedForMatching).filter { $0.count >= 4 }
        }
    }

    /// - Parameters:
    ///   - installed: every installed app, including helpers inside apps and
    ///     apps outside the Applications folders; the list must be complete,
    ///     or the files of a missing app would be reported as orphaned.
    ///   - runningBundleIDs: apps running now, which count as installed.
    ///   - extraIdentifiers: other identifiers apps bring along, such as
    ///     launchd labels.
    ///   - progress: told which folder is being read and which item is being
    ///     measured, for the interface to show.
    func find(installed: [InstalledApp], runningBundleIDs: Set<String>, ignored: Set<String>,
              extraIdentifiers: Set<String> = [], progress: ScanProgressReporter? = nil) throws -> [OrphanItem] {
        guard !installed.isEmpty else { throw ScanError.incompleteAppList }
        let known = KnownApps(installed: installed, runningBundleIDs: runningBundleIDs, extraIdentifiers: extraIdentifiers)

        var items: [OrphanItem] = []
        for folder in searchFolders where protected?.contains(folder) != true {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { continue }
            progress?.report(folder)
            let identifiersOnly = bundleIdentifierOnlyFolders.contains { PathPolicy.isSame(folder.path, $0) }
            for name in names {
                try Task.checkCancellation()
                let url = folder.appendingPathComponent(name)
                guard !ignored.contains(url.path), !OrphanSkipList.contains(name),
                      !identifiersOnly || LeftoverFinder.looksLikeBundleIdentifier(Self.withoutKnownExtension(name)),
                      !Self.belongsToKnownApp(name, known: known),
                      !isRegisteredApp(named: name),
                      case .allowed(let canonical) = policy.evaluate(url, purpose: .orphan),
                      let identity = FileIdentity.of(canonical) else { continue }
                progress?.report(canonical)
                let size = try AllocatedSizeCalculator().measure(canonical)
                guard size.bytes > 0 else { continue }
                items.append(OrphanItem(url: canonical, identity: identity, bytes: size.reclaimableBytes,
                                        isDirectory: CategoryResultBuilder.isDirectory(canonical),
                                        lastModified: size.latestModification,
                                        requiresAdministrator: RemovalService.needsAdministrator(canonical)))
            }
        }
        return items.sorted { $0.bytes > $1.bytes }
    }

    /// True when the name points at an installed or running app, either
    /// because it contains the app's name or identifier, because it starts
    /// with the app's name, or because it is part of an identifier, as
    /// "Google" is part of "com.google.Chrome".
    static func belongsToKnownApp(_ name: String, known: KnownApps) -> Bool {
        if known.matchers.contains(where: { $0.match(name) != nil }) { return true }
        let normalized = (name as NSString).deletingPathExtension.normalizedForMatching
        guard normalized.count >= 4 else { return true }
        return known.identifiers.contains { $0.contains(normalized) || normalized.contains($0) }
            || known.names.contains { normalized.hasPrefix($0) }
    }

    /// Asks LaunchServices about the name as an identifier, and about each
    /// identifier it extends: com.vendor.app.helper belongs to com.vendor.app.
    private func isRegisteredApp(named name: String) -> Bool {
        var parts = Self.withoutKnownExtension(name).split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty && !$0.contains(" ") }) else { return false }
        while parts.count >= 3 {
            if isRegistered(parts.joined(separator: ".")) { return true }
            parts.removeLast()
        }
        return false
    }

    private static func withoutKnownExtension(_ name: String) -> String {
        AppMatcher.ignoredExtensions.contains((name as NSString).pathExtension.lowercased())
            ? (name as NSString).deletingPathExtension : name
    }
}
