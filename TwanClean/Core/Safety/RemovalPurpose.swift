import Foundation

/// How an item leaves the disk.
enum RemovalMode: Sendable {
    /// Unlinked immediately. Reserved for data the system or an app recreates.
    case delete
    /// Moved to the Trash so the user can still recover it.
    case trash
}

/// Why an item is being removed. The purpose decides both where removal is
/// allowed and how the item is removed, so a feature cannot pick a mode that
/// its data does not justify.
enum RemovalPurpose: String, Sendable, CaseIterable {
    /// Caches, logs and build products that are recreated on demand.
    case regenerableCache
    /// Items already in the user's Trash.
    case trashContents
    /// A user's own file, such as a large download or an AI chat history.
    case userFile
    /// An Xcode archive. Its debug symbols cannot be rebuilt, so it is never
    /// deleted outright.
    case buildArchive
    /// An application bundle.
    case appBundle
    /// Support files an application left in a Library folder.
    case appLeftover
    /// Files left behind by an application that is no longer installed.
    case orphan

    var mode: RemovalMode {
        switch self {
        case .regenerableCache, .trashContents:
            .delete
        case .userFile, .buildArchive, .appBundle, .appLeftover, .orphan:
            .trash
        }
    }
}
