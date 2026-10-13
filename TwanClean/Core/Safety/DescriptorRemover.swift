import Foundation

/// Deletes a file or folder tree relative to open directory descriptors.
///
/// `FileManager.removeItem` walks the tree by path, so a folder inside the
/// tree that is swapped for a symlink while the walk runs would send the
/// remaining deletions through the link. Here every folder is opened with
/// `O_NOFOLLOW | O_DIRECTORY` and everything in it is unlinked through that
/// descriptor, so a swap can at most make one step fail. The walk never leaves
/// the volume of the item it was asked to remove: a mounted volume found inside
/// is left untouched and reported.
enum DescriptorRemover {
    enum Failure: Error, Equatable {
        /// A volume is mounted inside the tree; everything else was removed.
        case mountPoint(String)
        /// The item is no longer the object that was scanned.
        case changed(String)
    }

    /// Removes the item at `url`, which must still be the object `identity`
    /// describes. A symlink is unlinked itself, never followed.
    /// `afterListing` runs once a folder's entries are read and before they are
    /// removed; tests use it to change the tree mid-walk.
    static func remove(_ url: URL, expecting identity: FileIdentity,
                       afterListing: @escaping (String) -> Void = { _ in }) throws {
        let path = url.path
        let parentPath = url.deletingLastPathComponent().path
        let name = Array(url.lastPathComponent.utf8CString)

        let parent = open(parentPath, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard parent >= 0 else { throw posixError(errno, parentPath) }
        defer { close(parent) }
        var parentStatus = stat()
        guard fstat(parent, &parentStatus) == 0 else { throw posixError(errno, parentPath) }

        var status = stat()
        guard fstatat(parent, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else { throw posixError(errno, path) }
        // Compared through the opened parent, so a folder swapped in since the
        // path was checked does not match.
        guard FileIdentity(status) == identity else { throw Failure.changed(path) }
        guard status.st_dev == parentStatus.st_dev else { throw Failure.mountPoint(path) }

        let walk = Walk(device: status.st_dev, afterListing: afterListing)
        do {
            if isDirectory(status) {
                try walk.removeDirectory(name, in: parent, path: path, status: status)
            } else {
                try walk.unlink(name, in: parent, path: path, directory: false)
            }
        } catch {
            if let mount = walk.mountPoint { throw Failure.mountPoint(mount) }
            throw error
        }
        if let mount = walk.mountPoint { throw Failure.mountPoint(mount) }
    }

    private static func isDirectory(_ status: stat) -> Bool {
        (status.st_mode & S_IFMT) == S_IFDIR
    }

    private static func posixError(_ code: Int32, _ path: String) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: path])
    }

    private struct Child {
        /// The raw name, NUL-terminated, so names that are not valid UTF-8 are
        /// still removed exactly.
        let name: [CChar]
        let type: UInt8
    }

    private final class Walk {
        let device: dev_t
        let afterListing: (String) -> Void
        /// The first mounted volume found inside the tree.
        var mountPoint: String?

        init(device: dev_t, afterListing: @escaping (String) -> Void) {
            self.device = device
            self.afterListing = afterListing
        }

        func removeDirectory(_ name: [CChar], in parent: Int32, path: String, status: stat) throws {
            guard status.st_dev == device else {
                mountPoint = mountPoint ?? path
                return
            }
            let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else {
                if errno == ENOENT { return }
                throw DescriptorRemover.posixError(errno, path)
            }
            defer { close(fd) }
            var opened = stat()
            guard fstat(fd, &opened) == 0 else { throw DescriptorRemover.posixError(errno, path) }
            guard opened.st_dev == status.st_dev, opened.st_ino == status.st_ino else {
                throw Failure.changed(path)
            }

            let children = try list(fd, path: path)
            afterListing(path)
            var firstError: Error?
            for child in children {
                let childPath = path + "/" + String(cString: child.name)
                do {
                    try removeChild(child, in: fd, path: childPath)
                } catch {
                    firstError = firstError ?? error
                }
            }
            if let firstError { throw firstError }
            // A mounted volume left inside keeps its folders non-empty.
            if mountPoint != nil { return }
            try unlink(name, in: parent, path: path, directory: true)
        }

        private func removeChild(_ child: Child, in parent: Int32, path: String) throws {
            // Anything the listing says is not a folder is unlinked as it is.
            // Should it have become a folder since, `unlinkat` refuses.
            guard child.type == UInt8(DT_DIR) || child.type == UInt8(DT_UNKNOWN) else {
                try unlink(child.name, in: parent, path: path, directory: false)
                return
            }
            var status = stat()
            guard fstatat(parent, child.name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
                if errno == ENOENT { return }
                throw DescriptorRemover.posixError(errno, path)
            }
            if DescriptorRemover.isDirectory(status) {
                try removeDirectory(child.name, in: parent, path: path, status: status)
            } else {
                try unlink(child.name, in: parent, path: path, directory: false)
            }
        }

        func unlink(_ name: [CChar], in parent: Int32, path: String, directory: Bool) throws {
            guard unlinkat(parent, name, directory ? AT_REMOVEDIR : 0) == 0 else {
                if errno == ENOENT { return }
                throw DescriptorRemover.posixError(errno, path)
            }
        }

        private func list(_ fd: Int32, path: String) throws -> [Child] {
            // `fdopendir` takes over the descriptor it is given.
            let copy = dup(fd)
            guard copy >= 0 else { throw DescriptorRemover.posixError(errno, path) }
            guard let directory = fdopendir(copy) else {
                let code = errno
                close(copy)
                throw DescriptorRemover.posixError(code, path)
            }
            defer { closedir(directory) }

            var children: [Child] = []
            errno = 0
            while let entry = readdir(directory) {
                let length = Int(entry.pointee.d_namlen)
                let name: [CChar] = withUnsafePointer(to: &entry.pointee.d_name) { tuple in
                    tuple.withMemoryRebound(to: CChar.self, capacity: length + 1) {
                        Array(UnsafeBufferPointer(start: $0, count: length + 1))
                    }
                }
                if name == [46, 0] || name == [46, 46, 0] { continue }  // "." and ".."
                children.append(Child(name: name, type: entry.pointee.d_type))
            }
            if errno != 0 { throw DescriptorRemover.posixError(errno, path) }
            return children
        }
    }
}
