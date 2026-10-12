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
    ///   strongly is listed but not selected.
    func find(for app: InstalledApp, sensitivity: SearchSensitivity, otherApps: [InstalledApp] = []) throws -> LeftoverScan {
        // Apple's own apps share support folders (GarageBand and Logic, for
        // instance), so only files named exactly after them are considered.
        let isAppleApp = app.bundleIdentifier.lowercased().hasPrefix("com.apple.")
        let matcher = AppMatcher(app: app, sensitivity: isAppleApp ? .strict : sensitivity)
        let others = otherApps.filter { $0.bundleIdentifier.caseInsensitiveCompare(app.bundleIdentifier) != .orderedSame }
            .map { AppMatcher(app: $0, sensitivity: .enhanced) }
        var scan = LeftoverScan()
        var matches: [URL: AppMatcher.Match] = [:]

        func isLocked(_ folder: URL) -> Bool {
            guard protected?.contains(folder) == true else { return false }
            if FileIdentity.of(folder) != nil, !scan.lockedLocations.contains(folder) { scan.lockedLocations.append(folder) }
            return true
        }

        func consider(_ folder: URL, searchVendors: Bool) {
            guard !isLocked(folder),
                  let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
            for name in names {
                let url = folder.appendingPathComponent(name)
                if let match = matcher.match(name) {
                    if matches[url] == nil { matches[url] = match }
                } else if searchVendors, Self.isDirectory(url), protected?.contains(url) != true,
                          let children = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
                    for child in children {
                        if let match = matcher.match(child) { matches[url.appendingPathComponent(child)] = match }
                    }
                }
            }
        }

        for folder in Self.homeFolders {
            consider(home.appendingPathComponent(folder),
                     searchVendors: Self.vendorFolders.contains((folder as NSString).lastPathComponent))
        }
        for folder in systemFolders {
            consider(URL(fileURLWithPath: folder), searchVendors: (folder as NSString).lastPathComponent == "Application Support")
        }

        // Sandboxed apps often keep their data in a container named by UUID;
        // its metadata names the owner exactly.
        let containers = home.appendingPathComponent("Library/Containers")
        if !isLocked(containers) {
            for container in ContainerResolver.containers(in: containers, ownedBy: app.bundleIdentifier) {
                matches[container] = AppMatcher.Match(tier: .bundleIdentifier, isExact: true, length: .max)
            }
        }
        for folder in matcher.override?.extraFolders ?? [] {
            let url = home.appendingPathComponent(folder)
            if FileIdentity.of(url) != nil, protected?.contains(url) != true {
                matches[url] = AppMatcher.Match(tier: .override, isExact: true, length: .max)
            }
        }

        scan.items = try collect(matches, app: app, others: others)
        return scan
    }

    /// Measures the matches the policy allows, keeping only the outermost of
    /// nested paths and leaving out files another app claims, and decides
    /// what to preselect.
    private func collect(_ matches: [URL: AppMatcher.Match], app: InstalledApp, others: [AppMatcher]) throws -> [LeftoverItem] {
        var items: [LeftoverItem] = []
        if let bundle = try item(app.url, purpose: .appBundle, match: nil, shared: false) { items.append(bundle) }

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
            }
            if let leftover = try item(url, purpose: .appLeftover, match: match, shared: shared) {
                kept.append(url)
                items.append(leftover)
            }
        }
        return items.sorted { ($0.group.rawValue, -$0.bytes) < ($1.group.rawValue, -$1.bytes) }
    }

    private func item(_ url: URL, purpose: RemovalPurpose, match: AppMatcher.Match?, shared: Bool) throws -> LeftoverItem? {
        guard let identity = FileIdentity.of(url) else { return nil }
        let bytes = try AllocatedSizeCalculator().measure(url).bytes
        let needsAdministrator = RemovalService.needsAdministrator(url)
        // Selected for the user: the app itself, and files named exactly after
        // it or found through its container metadata. A file that only
        // contains the app's name is selected too, unless it needs a password,
        // may belong to another app, or was tied to the app only through its
        // developer.
        let preselect: Bool = switch match {
        case nil: true
        case .some(let match) where shared: false
        case .some(let match) where needsAdministrator: match.isExact
        case .some(let match): match.tier != .developerName && match.tier != .teamIdentifier
        }
        return LeftoverItem(url: url, identity: identity, bytes: bytes, isDirectory: Self.isDirectory(url),
                            purpose: purpose, group: LeftoverItem.group(for: url), tier: match?.tier,
                            mayBelongToAnotherApp: shared,
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
