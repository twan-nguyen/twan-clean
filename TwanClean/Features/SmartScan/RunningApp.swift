import AppKit

/// What the scan knows about a running app, captured once so scanners never
/// ask the system themselves and tests can describe any set of apps.
struct RunningApp: Hashable, Sendable {
    var bundleID: String?
    var name: String?
    var executableName: String?

    init(bundleID: String? = nil, name: String? = nil, executableName: String? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.executableName = executableName
    }

    /// The apps running now.
    @MainActor
    static func current() -> [RunningApp] {
        NSWorkspace.shared.runningApplications.map {
            RunningApp(bundleID: $0.bundleIdentifier, name: $0.localizedName,
                       executableName: $0.executableURL?.lastPathComponent)
        }
    }
}

/// Decides whether a cache folder belongs to a running app. Folders are named
/// after the bundle identifier (com.google.Chrome), the app (Google Chrome) or
/// the vendor (Google), so all of those are compared, ignoring case.
struct RunningAppIndex: Sendable {
    private let bundleIDs: Set<String>
    private let names: Set<String>

    /// Vendor names too generic to say anything about a folder.
    private static let ignoredVendors: Set<String> = ["apple"]

    init(bundleIDs: Set<String> = [], apps: [RunningApp] = []) {
        var ids = Set(bundleIDs.map { $0.lowercased() })
        var names = Set<String>()
        for app in apps {
            if let id = app.bundleID?.lowercased(), !id.isEmpty {
                ids.insert(id)
            }
            for name in [app.name, app.executableName] {
                if let name = name?.lowercased(), name.count >= 3 { names.insert(name) }
            }
        }
        for id in ids {
            if let vendor = Self.vendor(of: id) { names.insert(vendor) }
        }
        self.bundleIDs = ids
        self.names = names
    }

    /// "google" for "com.google.chrome". Only identifiers with a vendor and a
    /// product have one.
    static func vendor(of bundleID: String) -> String? {
        let parts = bundleID.lowercased().split(separator: ".")
        guard parts.count >= 3 else { return nil }
        let vendor = String(parts[1])
        return vendor.count >= 3 && !ignoredVendors.contains(vendor) ? vendor : nil
    }

    var bundleIdentifiers: Set<String> { bundleIDs }

    /// Whether an item called `folderName` is the data of a running app, or
    /// one of the `owners` the scanner knows to be running.
    func owns(folderNamed folderName: String, owners: Set<String> = []) -> Bool {
        var name = folderName.lowercased()
        for suffix in [".savedstate", ".binarycookies"] where name.hasSuffix(suffix) {
            name.removeLast(suffix.count)
        }
        if bundleIDs.contains(name) || names.contains(name) { return true }
        if bundleIDs.contains(where: { name.hasPrefix($0 + ".") }) { return true }
        return owners.contains { owner in
            let owner = owner.lowercased()
            return bundleIDs.contains(owner) || names.contains(owner)
        }
    }
}
