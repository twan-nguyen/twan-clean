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
}
