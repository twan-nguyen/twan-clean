import Foundation

/// Folders macOS guards with its privacy controls. Reading inside one without
/// Full Disk Access makes macOS interrupt the user with a permission prompt,
/// so until access is granted the app leaves them alone and shows them as
/// locked instead.
struct ProtectedLocations: Sendable {
    let roots: [String]
    /// A folder the user picked in an Open panel. macOS treats that choice as
    /// consent to read that folder, but not other protected folders below it.
    let consentedFolder: String?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, consentedFolder: URL? = nil) {
        let home = SafetyRules(homeDirectory: home).home
        roots = [
            "Desktop", "Documents", "Downloads", "Pictures", "Music", "Movies", ".Trash",
            "Library/Mobile Documents", "Library/CloudStorage",
            "Library/Containers", "Library/Group Containers",
            "Library/Mail", "Library/Messages", "Library/Safari", "Library/Calendars", "Library/Reminders",
            "Library/Cookies", "Library/HomeKit", "Library/IdentityServices", "Library/Suggestions",
            "Library/PersonalizationPortrait", "Library/Metadata/CoreSpotlight", "Library/Accounts",
            "Library/Application Support/AddressBook", "Library/Application Support/CallHistoryDB",
            "Library/Application Support/Knowledge", "Library/Application Support/com.apple.TCC",
        ].map { "\(home)/\($0)" } + ["/Library/Application Support/com.apple.TCC", "/Volumes"]
        self.consentedFolder = consentedFolder.map { SafetyRules.canonicalPath($0.path) ?? $0.path }
    }

    /// Whether reading `url` could make macOS ask for permission.
    func contains(_ url: URL) -> Bool {
        let path = url.path
        return roots.contains { root in
            guard PathPolicy.isSame(path, root) || PathPolicy.isInside(path, root) else { return false }
            // Consent covers a protected folder only when the chosen folder is
            // that folder or inside it. Choosing the home folder does not open
            // up Documents or other apps' data below it.
            guard let consentedFolder else { return true }
            let consentCoversRoot = PathPolicy.isSame(consentedFolder, root) || PathPolicy.isInside(consentedFolder, root)
            let pathIsInConsent = PathPolicy.isSame(path, consentedFolder) || PathPolicy.isInside(path, consentedFolder)
            return !(consentCoversRoot && pathIsInConsent)
        }
    }

    /// The locations to avoid right now: none once Full Disk Access is
    /// granted, since nothing will prompt then.
    static func current(consentedFolder: URL? = nil) -> ProtectedLocations? {
        FullDiskAccess.isGranted() ? nil : ProtectedLocations(consentedFolder: consentedFolder)
    }
}
