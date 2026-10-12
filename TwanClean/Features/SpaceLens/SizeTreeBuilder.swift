import Foundation

/// Builds the Space Lens tree of a folder: actual allocated bytes, hard links
/// counted once, symlinks never followed, bundles treated as single files and
/// unreadable folders marked. The top-level folders are walked in parallel.
struct SizeTreeBuilder: Sendable {
    /// Items smaller than this are folded into their folder.
    let minimumNodeBytes: Int64

    init(minimumNodeBytes: Int64 = 1 << 20) {
        self.minimumNodeBytes = minimumNodeBytes
    }

    /// Builds the tree of `root`. Folders in `protected` are not read; they
    /// appear as locked items so macOS never prompts mid-scan.
    func build(_ root: URL, progress: ScanProgressReporter = ScanProgressReporter(),
               protected: ProtectedLocations? = nil) async throws -> SizeNode {
        let sizing = AllocatedSizeCalculator(session: SizingSession())
        let rootNode = SizeNode(name: root.lastPathComponent, kind: .folder, identity: FileIdentity.of(root),
                                rootURL: root)
        if protected?.contains(root) == true {
            rootNode.isAccessDenied = true
            rootNode.finish()
            return rootNode
        }
        let entries: [String]
        do {
            entries = try FileManager.default.contentsOfDirectory(atPath: root.path)
        } catch {
            rootNode.isAccessDenied = true
            rootNode.finish()
            return rootNode
        }

        let limit = max(2, ProcessInfo.processInfo.activeProcessorCount)
        let builder = self
        let children = try await withThrowingTaskGroup(of: SizeNode?.self) { group in
            var pending = entries.makeIterator()
            func startNext() -> Bool {
                guard let name = pending.next() else { return false }
                let url = root.appendingPathComponent(name)
                group.addTask { try builder.node(for: url, sizing: sizing, progress: progress, protected: protected) }
                return true
            }
            for _ in 0..<limit where !startNext() { break }
            var nodes: [SizeNode] = []
            while let node = try await group.next() {
                if let node { nodes.append(node) }
                _ = startNext()
            }
            return nodes
        }

        for child in children {
            attach(child, to: rootNode)
        }
        rootNode.finish()
        return rootNode
    }

    /// The node for one entry of the root folder.
    private func node(for url: URL, sizing: AllocatedSizeCalculator, progress: ScanProgressReporter,
                      protected: ProtectedLocations?) throws -> SizeNode? {
        var status = stat()
        guard lstat(url.path, &status) == 0 else { return nil }
        let identity = FileIdentity(status)
        let name = url.lastPathComponent
        if protected?.contains(url) == true {
            return Self.lockedNode(name: name, identity: identity)
        }
        switch status.st_mode & S_IFMT {
        case S_IFDIR where Self.isPackage(name):
            return SizeNode(name: name, kind: .package, identity: identity, bytes: try sizing.measure(url).bytes)
        case S_IFDIR:
            return try walkFolder(url, sizing: sizing, progress: progress, protected: protected)
        case S_IFLNK:
            return SizeNode(name: name, kind: .symlink, identity: identity, bytes: Int64(status.st_blocks) * 512)
        default:
            if status.st_nlink > 1, !sizing.session.claim(identity) { return nil }
            return SizeNode(name: name, kind: .file, identity: identity, bytes: Int64(status.st_blocks) * 512)
        }
    }

    private func walkFolder(_ url: URL, sizing: AllocatedSizeCalculator, progress: ScanProgressReporter,
                            protected: ProtectedLocations?) throws -> SizeNode? {
        var stack: [SizeNode] = []
        var result: SizeNode?

        func close(_ node: SizeNode) {
            node.finish()
            if let parent = stack.last {
                attach(node, to: parent)
            } else {
                result = node
            }
        }

        try FileTreeWalker.walk(url) { entry in
            switch entry.kind {
            case .directory:
                if entry.depth > 0, protected?.contains(URL(fileURLWithPath: entry.path)) == true {
                    stack.last?.addChild(Self.lockedNode(name: entry.name, identity: entry.identity))
                    return .skipDescendants
                }
                if entry.depth > 0, Self.isPackage(entry.name) {
                    let bytes = try sizing.measure(URL(fileURLWithPath: entry.path)).bytes
                    attach(SizeNode(name: entry.name, kind: .package, identity: entry.identity, bytes: bytes),
                           to: stack.last!)
                    return .skipDescendants
                }
                progress.report(URL(fileURLWithPath: entry.path))
                stack.append(SizeNode(name: entry.name, kind: .folder, identity: entry.identity))
            case .directoryEnd, .unreadableDirectory:
                // fts reports an unreadable folder in place of its end.
                guard let node = stack.popLast() else { break }
                if entry.kind == .unreadableDirectory { node.isAccessDenied = true }
                close(node)
            case .file, .symlink:
                guard let parent = stack.last else { break }
                if entry.linkCount > 1, let identity = entry.identity, !sizing.session.claim(identity) {
                    break
                }
                attach(SizeNode(name: entry.name, kind: entry.kind == .file ? .file : .symlink,
                                identity: entry.identity, bytes: entry.allocatedBytes), to: parent)
            case .unreadable:
                stack.last?.isAccessDenied = true
            }
            return .continue
        }
        return result
    }

    /// Keeps a finished node as a child when it is big enough or needs the
    /// user's attention; otherwise folds its space into the parent.
    private func attach(_ node: SizeNode, to parent: SizeNode) {
        if node.bytes >= minimumNodeBytes || node.isAccessDenied {
            parent.addChild(node)
        } else {
            parent.addPruned(bytes: node.bytes, count: 1)
        }
    }

    /// A protected folder shown without being read.
    private static func lockedNode(name: String, identity: FileIdentity?) -> SizeNode {
        let node = SizeNode(name: name, kind: .folder, identity: identity)
        node.isAccessDenied = true
        return node
    }

    static func isPackage(_ name: String) -> Bool {
        LargeOldFilesScanner.packageExtensions.contains((name as NSString).pathExtension.lowercased())
    }
}
