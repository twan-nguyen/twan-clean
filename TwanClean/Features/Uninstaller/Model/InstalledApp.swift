import Foundation

/// An application found in /Applications or ~/Applications.
struct InstalledApp: Identifiable, Hashable, Sendable {
    let url: URL
    let bundleIdentifier: String
    let name: String
    let version: String?
    let identity: FileIdentity
    /// The Developer ID team that signed the app, when there is one.
    let teamIdentifier: String?

    var id: String { url.path }

    /// The `.app` file name without its extension.
    var fileStem: String { url.deletingPathExtension().lastPathComponent }
}
