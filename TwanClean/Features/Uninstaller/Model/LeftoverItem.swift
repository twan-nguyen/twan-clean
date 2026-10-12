import Foundation

/// A file or folder that belongs to an app being uninstalled.
struct LeftoverItem: Identifiable, Hashable, Sendable {
    enum Group: Int, CaseIterable, Sendable {
        case application
        case supportFiles
        case caches
        case preferences
        case containers
        case logs
        case launchItems
        case other

        var title: LocalizedStringResource {
            switch self {
            case .application: "Application"
            case .supportFiles: "Support Files"
            case .caches: "Caches"
            case .preferences: "Preferences"
            case .containers: "Containers"
            case .logs: "Logs"
            case .launchItems: "Launch Items"
            case .other: "Other"
            }
        }
    }

    let url: URL
    let identity: FileIdentity
    let bytes: Int64
    let isDirectory: Bool
    let purpose: RemovalPurpose
    let group: Group
    /// Which rule matched; nil for the app itself and for containers found
    /// through their metadata.
    let tier: MatchTier?
    /// Another installed app matches the name just as well.
    let mayBelongToAnotherApp: Bool
    let requiresAdministrator: Bool
    let selectedByDefault: Bool

    var id: String { url.path }
    var name: String { url.lastPathComponent }

    var removalRequest: RemovalRequest {
        RemovalRequest(url: url, purpose: purpose, identity: identity, bytes: bytes)
    }

    static func group(for url: URL) -> Group {
        let path = url.path
        func under(_ folder: String) -> Bool { path.contains("/Library/\(folder)/") }
        if url.pathExtension == "app" { return .application }
        if under("Caches") || under("HTTPStorages") || under("WebKit") { return .caches }
        if under("Preferences") { return .preferences }
        if under("Containers") || under("Group Containers") || under("Application Scripts") { return .containers }
        if under("Logs") { return .logs }
        if under("LaunchAgents") || under("LaunchDaemons") || under("PrivilegedHelperTools") { return .launchItems }
        if under("Application Support") || under("Saved Application State") { return .supportFiles }
        return .other
    }
}
