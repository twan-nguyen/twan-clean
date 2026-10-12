import Foundation
import Security

/// Finds the apps the user can uninstall.
struct InstalledAppIndex: Sendable {
    let roots: [URL]
    /// Apps are looked for this many folders deep, e.g. /Applications/Utilities.
    let maximumDepth: Int

    init(roots: [URL] = [URL(fileURLWithPath: "/Applications"),
                         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")],
         maximumDepth: Int = 3) {
        self.roots = roots
        self.maximumDepth = maximumDepth
    }

    func apps() -> [InstalledApp] {
        var found: [String: InstalledApp] = [:]
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants, .skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                if enumerator.level > maximumDepth {
                    enumerator.skipDescendants()
                    continue
                }
                guard url.pathExtension.lowercased() == "app", let app = Self.app(at: url),
                      found[app.bundleIdentifier.lowercased()] == nil else { continue }
                found[app.bundleIdentifier.lowercased()] = app
            }
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The app at `url`, unless it is part of macOS or otherwise protected.
    static func app(at url: URL) -> InstalledApp? {
        let path = url.resolvingSymlinksInPath().path
        guard !path.hasPrefix("/System/"),
              let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let bundleIdentifier = info["CFBundleIdentifier"] as? String,
              !bundleIdentifier.isEmpty, !ProtectedApps.contains(bundleIdentifier),
              let identity = FileIdentity.of(url) else { return nil }
        let name = (info["CFBundleDisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (info["CFBundleName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApp(url: url, bundleIdentifier: bundleIdentifier, name: name,
                            version: info["CFBundleShortVersionString"] as? String, identity: identity,
                            teamIdentifier: teamIdentifier(of: url))
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
