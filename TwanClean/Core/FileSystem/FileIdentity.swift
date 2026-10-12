import Foundation

/// Identifies one file system object independently of its path, so removal can
/// confirm the item is the one that was scanned and a hard-linked file is only
/// counted once.
struct FileIdentity: Hashable, Sendable {
    let device: Int64
    let inode: UInt64

    init(device: Int64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }

    init(_ status: stat) {
        self.init(device: Int64(status.st_dev), inode: UInt64(status.st_ino))
    }

    /// Identity of the item at `path` itself; a symlink is not followed.
    static func of(path: String) -> FileIdentity? {
        var status = stat()
        guard lstat(path, &status) == 0 else { return nil }
        return FileIdentity(status)
    }

    static func of(_ url: URL) -> FileIdentity? {
        of(path: url.path)
    }

    enum Lookup: Equatable {
        case found(FileIdentity)
        case missing
        /// The item may exist but cannot be examined, e.g. for lack of access.
        case unexaminable
    }

    /// Like `of(path:)`, but tells a missing item from one that cannot be
    /// examined, so an inaccessible file is never reported as already gone.
    static func lookup(_ url: URL) -> Lookup {
        var status = stat()
        if lstat(url.path, &status) == 0 { return .found(FileIdentity(status)) }
        return errno == ENOENT || errno == ENOTDIR ? .missing : .unexaminable
    }

    /// Whether the item is the root of a mounted volume, which removal must
    /// never descend into.
    static func isMountPoint(_ url: URL) -> Bool {
        var item = stat()
        var parent = stat()
        guard lstat(url.path, &item) == 0, lstat(url.deletingLastPathComponent().path, &parent) == 0 else {
            return false
        }
        return item.st_dev != parent.st_dev
    }
}
