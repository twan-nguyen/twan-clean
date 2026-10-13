import Foundation
import Security

/// Finds the apps the user can uninstall, and the other apps on this Mac whose
/// files must not be taken for someone else's.
struct InstalledAppIndex: Sendable {
    let roots: [URL]
    /// Apps are looked for this many folders deep, e.g. /Applications/Utilities
    /// or /Applications/Setapp.
    let maximumDepth: Int
    /// Also list macOS's own apps, which cannot be uninstalled but whose
    /// files must never be mistaken for orphans.
    let includesProtectedApps: Bool
    /// Where else apps live (Spotlight's list, in the real index): other
    /// volumes, /Users/Shared, folders that are not in `roots`. They are never
    /// offered for uninstalling, only counted as installed.
    let additionalApplications: (@Sendable () -> [URL])?

    static let userRoots = [URL(fileURLWithPath: "/Applications"),
                            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
    static let systemRoots = [URL(fileURLWithPath: "/System/Applications"),
                              URL(fileURLWithPath: "/System/Library/CoreServices")]

    /// The apps the user can uninstall, plus what else is installed.
    static var standard: InstalledAppIndex {
        InstalledAppIndex(additionalApplications: SpotlightApplications.urls)
    }

    /// Everything installed, macOS's own apps included, for deciding what is
    /// left behind by an app that is gone.
    static var everything: InstalledAppIndex {
        InstalledAppIndex(roots: userRoots + systemRoots, includesProtectedApps: true,
                          additionalApplications: SpotlightApplications.urls)
    }

    init(roots: [URL] = InstalledAppIndex.userRoots, maximumDepth: Int = 3, includesProtectedApps: Bool = false,
         additionalApplications: (@Sendable () -> [URL])? = nil) {
        self.roots = roots
        self.maximumDepth = maximumDepth
        self.includesProtectedApps = includesProtectedApps
        self.additionalApplications = additionalApplications
    }

    /// The apps the user can uninstall. Two copies with the same bundle
    /// identifier are both listed.
    func apps() -> [InstalledApp] {
        scanRoots().listed.sorted(by: Self.listOrder)
    }

    /// The listed apps and everything else installed.
    func catalog() -> AppCatalog {
        let scan = scanRoots()
        var catalog = AppCatalog(listed: scan.listed.sorted(by: Self.listOrder), related: scan.related,
                                 unreadableRoots: scan.unreadable)
        var known = Set((scan.listed + scan.related).map { SafetyRules.canonicalPath($0.url.path) ?? $0.url.path })

        for url in additionalApplications?() ?? [] where Self.isApplicationBundle(url) {
            let path = SafetyRules.canonicalPath(url.path) ?? url.path
            guard !known.contains(path), !path.contains("/.Trash/") else { continue }
            if Self.isInsideApplication(path) {
                if let app = Self.read(url, readingTeam: false) {
                    catalog.nested.append(app)
                    known.insert(path)
                }
            } else if !Self.isSymbolicLink(url), let app = Self.read(url, readingTeam: false) {
                catalog.related.append(app)
                known.insert(path)
            }
        }
        for app in scan.listed + scan.related {
            let helpers = NestedBundles.scan(app)
            for helper in helpers.apps where known.insert(helper.url.path).inserted { catalog.nested.append(helper) }
            catalog.extraIdentifiers.formUnion(helpers.identifiers)
        }
        return catalog
    }

    private static func listOrder(_ lhs: InstalledApp, _ rhs: InstalledApp) -> Bool {
        let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        return order == .orderedSame ? lhs.url.path < rhs.url.path : order == .orderedAscending
    }

    private struct RootScan {
        var listed: [InstalledApp] = []
        var related: [InstalledApp] = []
        var unreadable: [URL] = []
    }

    private func scanRoots() -> RootScan {
        var scan = RootScan()
        var seen = Set<String>()
        for root in roots {
            // Every Mac has /Applications; a missing ~/Applications is normal.
            let required = Self.requiredRoots.contains { PathPolicy.isSame(root.path, $0) }
            guard FileIdentity.of(root) != nil else {
                if required { scan.unreadable.append(root) }
                continue
            }
            var failed = false
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants, .skipsHiddenFiles],
                errorHandler: { _, _ in
                    failed = true
                    return true
                }) else {
                scan.unreadable.append(root)
                continue
            }
            for case let url as URL in enumerator {
                if enumerator.level > maximumDepth {
                    enumerator.skipDescendants()
                    continue
                }
                guard Self.isApplicationBundle(url), !Self.isSymbolicLink(url),
                      seen.insert(url.resolvingSymlinksInPath().path).inserted,
                      let app = Self.read(url) else { continue }
                if Self.isProtected(app) {
                    if includesProtectedApps { scan.listed.append(app) } else { scan.related.append(app) }
                } else {
                    scan.listed.append(app)
                }
            }
            if failed { scan.unreadable.append(root) }
        }
        return scan
    }

    private static let requiredRoots = ["/Applications"]

    /// The app at `url`, unless it is part of macOS or otherwise protected
    /// (and `includingProtected` is false), or only a link to an app that
    /// lives somewhere else.
    static func app(at url: URL, includingProtected: Bool = false) -> InstalledApp? {
        guard !isSymbolicLink(url), let app = read(url) else { return nil }
        return includingProtected || !isProtected(app) ? app : nil
    }

    /// Whether the last component of `url` is a symbolic link; the link
    /// itself, not what it points to, is what removal would move.
    static func isSymbolicLink(_ url: URL) -> Bool {
        var status = stat()
        return lstat(url.path, &status) == 0 && (status.st_mode & S_IFMT) == S_IFLNK
    }

    static func isProtected(_ app: InstalledApp) -> Bool {
        app.url.resolvingSymlinksInPath().path.hasPrefix("/System/") || ProtectedApps.contains(app.bundleIdentifier)
    }

    private static func isApplicationBundle(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "app"
    }

    private static func isInsideApplication(_ path: String) -> Bool {
        path.lowercased().contains(".app/")
    }

    /// Reads the bundle at `url` without judging whether it may be uninstalled.
    static func read(_ url: URL, readingTeam: Bool = true) -> InstalledApp? {
        guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let bundleIdentifier = info["CFBundleIdentifier"] as? String, !bundleIdentifier.isEmpty,
              let identity = FileIdentity.of(url) else { return nil }
        let name = (info["CFBundleDisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (info["CFBundleName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApp(url: url, bundleIdentifier: bundleIdentifier, name: name,
                            version: info["CFBundleShortVersionString"] as? String, identity: identity,
                            teamIdentifier: readingTeam ? teamIdentifier(of: url) : nil)
    }

    /// The signing team, read from the code signature without validating it.
    static func teamIdentifier(of url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess,
              let dictionary = information as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

/// What the index found.
struct AppCatalog: Sendable {
    /// Apps the user can uninstall.
    var listed: [InstalledApp] = []
    /// Other apps outside what can be uninstalled here: macOS's own, and those
    /// on other volumes or in folders the list does not cover.
    var related: [InstalledApp] = []
    /// Helper apps inside other apps, such as login items.
    var nested: [InstalledApp] = []
    /// Identifiers of things apps bring along that are not apps: launchd
    /// labels and privileged helper tools bundled inside an app.
    var extraIdentifiers: Set<String> = []
    /// Roots that should have been readable but were not.
    var unreadableRoots: [URL] = []

    /// Every app found, wherever it lives.
    var everyApp: [InstalledApp] { listed + related + nested }

    /// False when the answer cannot be trusted to be complete: a folder every
    /// Mac has could not be read, or there is nothing installed at all.
    var isComplete: Bool { unreadableRoots.isEmpty && !listed.isEmpty }
}

/// Apps and identifiers found inside an app bundle.
enum NestedBundles {
    /// Folders inside `Contents` that never hold helper apps and can be large.
    private static let skippedFolders: Set<String> = ["Resources", "_CodeSignature"]
    private static let maximumDepth = 4

    static func scan(_ app: InstalledApp) -> (apps: [InstalledApp], identifiers: Set<String>) {
        let contents = app.url.appendingPathComponent("Contents")
        var apps: [InstalledApp] = []
        if let enumerator = FileManager.default.enumerator(
            at: contents, includingPropertiesForKeys: nil, options: [.skipsPackageDescendants]) {
            for case let url as URL in enumerator {
                if enumerator.level > maximumDepth || skippedFolders.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
                if url.pathExtension.lowercased() == "app", !InstalledAppIndex.isSymbolicLink(url),
                   let helper = InstalledAppIndex.read(url, readingTeam: false) {
                    apps.append(helper)
                }
            }
        }
        return (apps, identifiers(in: app))
    }

    /// Launchd labels and privileged helper names the app declares.
    private static func identifiers(in app: InstalledApp) -> Set<String> {
        var found = Set<String>()
        let library = app.url.appendingPathComponent("Contents/Library")
        for folder in ["LaunchAgents", "LaunchDaemons"] {
            let plists = (try? FileManager.default.contentsOfDirectory(atPath: library.appendingPathComponent(folder).path)) ?? []
            for name in plists where name.hasSuffix(".plist") {
                if let label = Self.label(ofPlistAt: library.appendingPathComponent(folder).appendingPathComponent(name)) {
                    found.insert(label)
                }
            }
        }
        let tools = (try? FileManager.default.contentsOfDirectory(atPath: library.appendingPathComponent("LaunchServices").path)) ?? []
        found.formUnion(tools.filter { !$0.hasPrefix(".") })
        if let info = NSDictionary(contentsOf: app.url.appendingPathComponent("Contents/Info.plist")),
           let privileged = info["SMPrivilegedExecutables"] as? [String: Any] {
            found.formUnion(privileged.keys)
        }
        return found
    }

    /// The `Label` of a launchd property list, if it has one.
    static func label(ofPlistAt url: URL) -> String? {
        guard let plist = NSDictionary(contentsOf: url), let label = plist["Label"] as? String,
              !label.isEmpty else { return nil }
        return label
    }
}

/// Remembers app sizes between launches, keyed by path and modification
/// date, so the list does not re-measure every app each time it opens.
actor AppSizeCache {
    private struct Entry: Codable {
        let modified: Date
        let bytes: Int64
    }

    private let file: URL
    private var entries: [String: Entry]
    private var dirty = false

    init(file: URL = AppSizeCache.defaultFile) {
        self.file = file
        entries = (try? JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: file))) ?? [:]
    }

    static var defaultFile: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("TwanClean/app-sizes.json")
    }

    func size(of app: InstalledApp) throws -> Int64 {
        let modified = app.url.modificationDateWithoutFollowing ?? .distantPast
        if let entry = entries[app.url.path], entry.modified == modified {
            return entry.bytes
        }
        let bytes = try AllocatedSizeCalculator().measure(app.url).bytes
        entries[app.url.path] = Entry(modified: modified, bytes: bytes)
        dirty = true
        return bytes
    }

    func save() {
        guard dirty else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: file, options: .atomic)
            dirty = false
        }
    }
}
