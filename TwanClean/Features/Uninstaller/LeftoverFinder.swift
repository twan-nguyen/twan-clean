import Foundation

/// The files an app has left around the system, ready to review.
struct LeftoverScan: Sendable {
    var items: [LeftoverItem] = []
    /// Protected folders skipped because Full Disk Access is missing.
    var lockedLocations: [URL] = []
}

/// Looks through the Library folders where apps keep their files and
/// collects what belongs to one app. It never searches Documents, Desktop or
/// shared temporary folders, and only reports what the removal policy would
/// allow.
struct LeftoverFinder: Sendable {
    let home: URL
    let policy: PathPolicy
    let protected: ProtectedLocations?
    let systemFolders: [String]

    /// Library folders whose direct children are compared with the app.
    static let homeFolders = [
        "Library/Application Scripts", "Library/Application Support", "Library/Caches", "Library/Containers",
        "Library/Group Containers", "Library/HTTPStorages", "Library/Internet Plug-Ins", "Library/LaunchAgents",
        "Library/Logs", "Library/Logs/DiagnosticReports", "Library/Preferences", "Library/Preferences/ByHost",
        "Library/PreferencePanes", "Library/Saved Application State", "Library/Services", "Library/WebKit",
    ]

    /// Folders holding things the user made as much as things apps made:
    /// only a name equal to the app's counts there.
    static let exactOnlyFolders: Set<String> = ["Library/Services"]

    /// Folders where developers group their apps under a company name, e.g.
    /// Application Support/Google/Chrome; their grandchildren are compared too.
    static let vendorFolders: Set<String> = ["Application Support", "Caches", "Logs"]

    static let standardSystemFolders = [
        "/Library/Application Support", "/Library/Caches", "/Library/Logs", "/Library/Preferences",
        "/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools",
        "/private/var/db/receipts",
    ]

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, policy: PathPolicy = PathPolicy(),
         protected: ProtectedLocations? = nil, systemFolders: [String] = LeftoverFinder.standardSystemFolders) {
        self.home = home
        self.policy = policy
        self.protected = protected
        self.systemFolders = systemFolders
    }

    /// - Parameter otherApps: every other installed app. A file that one of
    ///   them claims more specifically is left out, and one they claim just as
    ///   strongly is listed but not selected. A second copy of `app` itself,
    ///   with the same bundle identifier, is not a rival: it keeps using the
    ///   app's shared files, so none of them is selected.
    func find(for app: InstalledApp, sensitivity: SearchSensitivity, otherApps: [InstalledApp] = []) throws -> LeftoverScan {
        // Apple's own apps share support folders (GarageBand and Logic, for
        // instance), so only files named exactly after them are considered.
        let isAppleApp = app.bundleIdentifier.lowercased().hasPrefix("com.apple.")
        let matcher = AppMatcher(app: app, sensitivity: isAppleApp ? .strict : sensitivity)
        func isCopy(_ other: InstalledApp) -> Bool {
            other.bundleIdentifier.caseInsensitiveCompare(app.bundleIdentifier) == .orderedSame
        }
        let anotherCopyRemains = otherApps.contains { isCopy($0) && $0.url.path != app.url.path }
        // Helpers inside the app are part of it, not competitors for its files.
        let others = otherApps.filter { !isCopy($0) && !PathPolicy.isInside($0.url.path, app.url.path) }
            .map { AppMatcher(app: $0, sensitivity: .enhanced) }
        let vendorKey = Self.developerKey(of: app)
        var scan = LeftoverScan()
        var matches: [URL: AppMatcher.Match] = [:]

        func isLocked(_ folder: URL) -> Bool {
            guard protected?.contains(folder) == true else { return false }
            if FileIdentity.of(folder) != nil, !scan.lockedLocations.contains(folder) { scan.lockedLocations.append(folder) }
            return true
        }

        /// A company folder that holds apps' folders, not one app's own data:
        /// named after the developer, and not the folder of an installed app.
        func isVendorFolder(_ url: URL) -> Bool {
            let name = url.lastPathComponent
            guard let vendorKey, name.normalizedForMatching.contains(vendorKey),
                  !Self.looksLikeBundleIdentifier(name), Self.isDirectory(url), protected?.contains(url) != true
            else { return false }
            return !claimedByAnyOf(others, url)
        }

        func consider(_ folder: URL, searchVendors: Bool, exactOnly: Bool) throws {
            guard !isLocked(folder),
                  let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
            for name in names {
                try Task.checkCancellation()
                let url = folder.appendingPathComponent(name)
                if let match = matcher.match(name) {
                    if matches[url] == nil, match.isExact || !exactOnly { matches[url] = match }
                } else if searchVendors, isVendorFolder(url),
                          let children = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
                    for child in children {
                        if let match = matcher.match(child) { matches[url.appendingPathComponent(child)] = match }
                    }
                }
            }
        }

        for folder in Self.homeFolders {
            try consider(home.appendingPathComponent(folder),
                         searchVendors: Self.vendorFolders.contains((folder as NSString).lastPathComponent),
                         exactOnly: Self.exactOnlyFolders.contains(folder))
        }
        for folder in systemFolders {
            try consider(URL(fileURLWithPath: folder),
                         searchVendors: (folder as NSString).lastPathComponent == "Application Support", exactOnly: false)
        }

        // Sandboxed apps often keep their data in a container named by UUID;
        // its metadata names the owner exactly.
        let containers = home.appendingPathComponent("Library/Containers")
        if !isLocked(containers) {
            for container in ContainerResolver.containers(in: containers, ownedBy: app.bundleIdentifier) {
                matches[container] = AppMatcher.Match(tier: .bundleIdentifier, isExact: true, length: .max)
            }
        }
        for folder in matcher.extraFolders {
            let url = home.appendingPathComponent(folder)
            if FileIdentity.of(url) != nil, protected?.contains(url) != true {
                matches[url] = AppMatcher.Match(tier: .override, isExact: true, length: .max)
            }
        }

        scan.items = try collect(matches, app: app, others: others, anotherCopyRemains: anotherCopyRemains)
        return scan
    }

    /// Whether an app in `others` owns `folder`: by its name, or as one of
    /// its override's folders.
    private func claimedByAnyOf(_ others: [AppMatcher], _ folder: URL) -> Bool {
        let name = folder.lastPathComponent
        let prefix = home.path + "/"
        let relative = folder.path.hasPrefix(prefix) ? String(folder.path.dropFirst(prefix.count)) : nil
        return others.contains { $0.match(name) != nil || (relative.map($0.claims(homeRelativeFolder:)) ?? false) }
    }

    /// The part of the bundle identifier that names the company, normalized:
    /// "google" for com.google.Chrome. Nil when it is too short to tell
    /// companies apart.
    static func developerKey(of app: InstalledApp) -> String? {
        let parts = app.bundleIdentifier.split(separator: ".").map(String.init)
        guard let part = parts.count >= 3 ? parts[1] : parts.first else { return nil }
        let key = part.normalizedForMatching
        return key.count >= 4 ? key : nil
    }

    /// Reverse-DNS names such as com.raycast.macos are one app's, never a
    /// company's folder of apps.
    static func looksLikeBundleIdentifier(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 3 && parts.allSatisfy { !$0.isEmpty && !$0.contains(" ") }
    }

    /// Measures the matches the policy allows, keeping only the outermost of
    /// nested paths and leaving out files another app claims, and decides
    /// what to preselect.
    private func collect(_ matches: [URL: AppMatcher.Match], app: InstalledApp, others: [AppMatcher],
                         anotherCopyRemains: Bool) throws -> [LeftoverItem] {
        var items: [LeftoverItem] = []
        if let bundle = try item(app.url, purpose: .appBundle, match: nil, shared: false, usedByAnotherCopy: false) {
            items.append(bundle)
        }

        let allowed = matches.compactMap { url, match -> (URL, AppMatcher.Match)? in
            guard case .allowed(let canonical) = policy.evaluate(url, purpose: .appLeftover) else { return nil }
            return (canonical, match)
        }.sorted { $0.0.path.count < $1.0.path.count }

        var kept: [URL] = []
        for (url, match) in allowed where !kept.contains(where: { PathPolicy.isSame(url.path, $0.path) || PathPolicy.isInside(url.path, $0.path) }) {
            try Task.checkCancellation()
            var shared = false
            if match.length != .max {
                let rivals = others.compactMap { $0.match(url.lastPathComponent) }
                if rivals.contains(where: { $0.length > match.length || ($0.isExact && !match.isExact) }) { continue }
                shared = rivals.contains { $0.length == match.length }
                // A company folder is only partly the app's when it also
                // holds the folders of other installed apps.
                if !shared, match.tier == .developerName, holdsFilesOfAnotherApp(url, others) { shared = true }
            }
            if let leftover = try item(url, purpose: .appLeftover, match: match, shared: shared,
                                       usedByAnotherCopy: anotherCopyRemains) {
                kept.append(url)
                items.append(leftover)
            }
        }
        return items.sorted { ($0.group.rawValue, -$0.bytes) < ($1.group.rawValue, -$1.bytes) }
    }

    private func holdsFilesOfAnotherApp(_ folder: URL, _ others: [AppMatcher]) -> Bool {
        guard Self.isDirectory(folder),
              let children = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return false }
        return children.contains { claimedByAnyOf(others, folder.appendingPathComponent($0)) }
    }

    private func item(_ url: URL, purpose: RemovalPurpose, match: AppMatcher.Match?, shared: Bool,
                      usedByAnotherCopy: Bool) throws -> LeftoverItem? {
        guard let identity = FileIdentity.of(url) else { return nil }
        let bytes = try AllocatedSizeCalculator().measure(url).bytes
        let needsAdministrator = RemovalService.needsAdministrator(url)
        // Selected for the user: the app itself, and files named exactly after
        // it, containing its whole bundle identifier, or found through its
        // container metadata. A file that only contains the app's name is
        // listed but left for the user to tick, as is one that needs a
        // password without being named exactly after the app, may belong to
        // another app, is still used by another copy of the app, or was tied
        // to the app only through its developer.
        let preselect: Bool
        if let match {
            preselect = !shared && !usedByAnotherCopy && match.isCertain
                && match.tier != .developerName && match.tier != .teamIdentifier
                && (!needsAdministrator || match.isExact)
        } else {
            preselect = true
        }
        return LeftoverItem(url: url, identity: identity, bytes: bytes, isDirectory: Self.isDirectory(url),
                            purpose: purpose, group: LeftoverItem.group(for: url), tier: match?.tier,
                            mayBelongToAnotherApp: shared, usedByAnotherCopy: usedByAnotherCopy && match != nil,
                            requiresAdministrator: needsAdministrator, selectedByDefault: preselect)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        CategoryResultBuilder.isDirectory(url)
    }
}

/// Finds sandbox containers by the owner recorded in their metadata.
enum ContainerResolver {
    static let metadataFile = ".com.apple.containermanagerd.metadata.plist"

    static func containers(in folder: URL, ownedBy bundleIdentifier: String) -> [URL] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.compactMap { name in
            let container = folder.appendingPathComponent(name)
            if name.caseInsensitiveCompare(bundleIdentifier) == .orderedSame { return container }
            guard let metadata = NSDictionary(contentsOf: container.appendingPathComponent(metadataFile)),
                  let owner = metadata["MCMMetadataIdentifier"] as? String,
                  owner.caseInsensitiveCompare(bundleIdentifier) == .orderedSame else { return nil }
            return container
        }
    }
}
