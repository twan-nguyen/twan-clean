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

    func find(for app: InstalledApp, sensitivity: SearchSensitivity) throws -> LeftoverScan {
        let matcher = AppMatcher(app: app, sensitivity: sensitivity)
        var scan = LeftoverScan()
        var matches: [URL: MatchTier?] = [:]

        func consider(_ folder: URL, searchVendors: Bool) {
            if protected?.contains(folder) == true {
                if FileIdentity.of(folder) != nil { scan.lockedLocations.append(folder) }
                return
            }
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
            for name in names {
                let url = folder.appendingPathComponent(name)
                if let tier = matcher.match(name) {
                    if matches[url] == nil { matches[url] = tier }
                } else if searchVendors, Self.isDirectory(url),
                          let children = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
                    for child in children {
                        if let tier = matcher.match(child) { matches[url.appendingPathComponent(child)] = tier }
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
        if protected?.contains(containers) != true {
            for container in ContainerResolver.containers(in: containers, ownedBy: app.bundleIdentifier) {
                matches[container] = .some(nil)
            }
        }
        for folder in matcher.override?.extraFolders ?? [] {
            let url = home.appendingPathComponent(folder)
            if FileIdentity.of(url) != nil, protected?.contains(url) != true { matches[url] = .override }
        }

        scan.items = try collect(matches, app: app)
        return scan
    }

    /// Measures the matches the policy allows, keeping only the outermost of
    /// nested paths, and decides what to preselect.
    private func collect(_ matches: [URL: MatchTier?], app: InstalledApp) throws -> [LeftoverItem] {
        var items: [LeftoverItem] = []
        if let bundle = try item(app.url, purpose: .appBundle, tier: nil) { items.append(bundle) }

        let allowed = matches.compactMap { url, tier -> (URL, MatchTier?)? in
            guard case .allowed(let canonical) = policy.evaluate(url, purpose: .appLeftover) else { return nil }
            return (canonical, tier)
        }.sorted { $0.0.path.count < $1.0.path.count }

        var kept: [URL] = []
        for (url, tier) in allowed where !kept.contains(where: { PathPolicy.isSame(url.path, $0.path) || PathPolicy.isInside(url.path, $0.path) }) {
            try Task.checkCancellation()
            if let leftover = try item(url, purpose: .appLeftover, tier: tier) {
                kept.append(url)
                items.append(leftover)
            }
        }
        return items.sorted { ($0.group.rawValue, -$0.bytes) < ($1.group.rawValue, -$1.bytes) }
    }

    private func item(_ url: URL, purpose: RemovalPurpose, tier: MatchTier?) throws -> LeftoverItem? {
        guard let identity = FileIdentity.of(url) else { return nil }
        let bytes = try AllocatedSizeCalculator().measure(url).bytes
        let needsAdministrator = RemovalService.needsAdministrator(url)
        // The app itself and items matched exactly or through container
        // metadata are selected for the user. Files tied only to the developer
        // could belong to their other apps, and system-level items need an
        // exact match.
        let preselect: Bool = switch tier {
        case nil: true
        case .some(let tier) where needsAdministrator: tier.isExact || tier == .override
        case .some(let tier): tier != .developerName && tier != .teamIdentifier
        }
        return LeftoverItem(url: url, identity: identity, bytes: bytes, isDirectory: Self.isDirectory(url),
                            purpose: purpose, group: LeftoverItem.group(for: url), tier: tier,
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
