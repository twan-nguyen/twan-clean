import Foundation

/// One thing Smart Scan offers to remove.
struct CleanableItem: Identifiable, Hashable, Sendable {
    enum Note: Hashable, Sendable {
        /// The app that owns this cache is running.
        case appIsRunning
        /// Part of the item could not be read, so its size is a lower bound.
        case partlyUnreadable
        /// Personal data, such as an AI chat history.
        case personalData
        /// Kept for a reason, such as Xcode archives used to symbolicate crashes.
        case mayBeNeeded
        /// Belongs to macOS. It is rebuilt, but some features may be slower
        /// until it is.
        case usedByMacOS
    }

    /// The canonical path.
    var id: String { url.path }
    let url: URL
    let category: CleanupCategoryID
    let identity: FileIdentity
    let isDirectory: Bool
    let bytes: Int64
    let purpose: RemovalPurpose
    let requiresAdministrator: Bool
    let selectedByDefault: Bool
    let lastModified: Date?
    let notes: Set<Note>

    var name: String { url.lastPathComponent }

    var removalRequest: RemovalRequest {
        RemovalRequest(url: url, purpose: purpose, identity: identity, bytes: bytes)
    }
}

/// What one category found.
struct CategoryResult: Sendable {
    let category: CleanupCategoryID
    var items: [CleanableItem]
    /// Space Docker reports it could reclaim, which only `docker system prune`
    /// can free safely. Shown for information.
    var dockerReclaimableBytes: Int64?
    /// Folders the scan could not read, usually for lack of Full Disk Access.
    var unreadableLocations: [URL] = []

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
}
