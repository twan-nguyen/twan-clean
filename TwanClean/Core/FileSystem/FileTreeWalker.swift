import Foundation

/// One item reported by `FileTreeWalker`.
struct FileTreeEntry {
    enum Kind {
        /// A directory, reported before its contents.
        case directory
        /// A directory, reported again after all its contents.
        case directoryEnd
        case file
        case symlink
        /// A directory whose contents could not be listed.
        case unreadableDirectory
        /// Anything else that could not be examined, including a missing root.
        case unreadable
    }

    let path: String
    let name: String
    /// 0 for the root passed to `walk`.
    let depth: Int
    let kind: Kind
    /// Bytes actually allocated on disk (`st_blocks * 512`), 0 for directories.
    let allocatedBytes: Int64
    let identity: FileIdentity?
    let linkCount: Int
    let modificationDate: Date?
}

/// A fast, cancellable walk of a file tree built on `fts(3)`. It never follows
/// symlinks, includes hidden files, has no item cap, and stays on the root's
/// volume.
enum FileTreeWalker {
    enum Action {
        case `continue`
        /// Do not descend into the directory just reported. Its
        /// `directoryEnd` is not reported either.
        case skipDescendants
    }

    /// How often the walk checks for task cancellation.
    static let cancellationInterval = 512

    static func walk(_ root: URL, visit: (FileTreeEntry) throws -> Action) throws {
        let options = FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV
        let rootPath = strdup(root.path)
        defer { free(rootPath) }
        var paths: [UnsafeMutablePointer<CChar>?] = [rootPath, nil]
        guard let stream = fts_open(&paths, options, nil) else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: root.path])
        }
        defer { fts_close(stream) }

        var visited = 0
        var skipped: UnsafeMutablePointer<FTSENT>?
        while let node = fts_read(stream) {
            // After FTS_SKIP, fts hands the same folder back as its end; the
            // caller never saw it open, so that end is not reported.
            if node == skipped, Int32(node.pointee.fts_info) == FTS_DP {
                skipped = nil
                continue
            }
            visited += 1
            if visited % cancellationInterval == 0 {
                try Task.checkCancellation()
            }
            let entry = makeEntry(node)
            if try visit(entry) == .skipDescendants, entry.kind == .directory {
                fts_set(stream, node, FTS_SKIP)
                skipped = node
            }
        }
    }

    private static func makeEntry(_ pointer: UnsafeMutablePointer<FTSENT>) -> FileTreeEntry {
        let node = pointer.pointee
        let path = String(cString: node.fts_path)
        let name = (path as NSString).lastPathComponent
        let kind: FileTreeEntry.Kind
        switch Int32(node.fts_info) {
        case FTS_D: kind = .directory
        case FTS_DP: kind = .directoryEnd
        case FTS_F, FTS_DEFAULT: kind = .file
        case FTS_SL, FTS_SLNONE: kind = .symlink
        case FTS_DNR: kind = .unreadableDirectory
        default: kind = .unreadable
        }

        var allocated: Int64 = 0
        var identity: FileIdentity?
        var linkCount = 1
        var modified: Date?
        if let status = node.fts_statp?.pointee, kind != .unreadable {
            identity = FileIdentity(status)
            linkCount = Int(status.st_nlink)
            modified = Date(timeIntervalSince1970: TimeInterval(status.st_mtimespec.tv_sec))
            if kind == .file || kind == .symlink {
                allocated = Int64(status.st_blocks) * 512
            }
        }
        return FileTreeEntry(path: path, name: name, depth: Int(node.fts_level), kind: kind,
                             allocatedBytes: allocated, identity: identity, linkCount: linkCount,
                             modificationDate: modified)
    }
}
