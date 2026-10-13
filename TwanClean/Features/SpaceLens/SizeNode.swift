import Foundation

/// One item in the Space Lens tree. Small items are not kept as nodes; their
/// space is folded into their folder's `prunedBytes` so huge trees stay light.
final class SizeNode: Identifiable, @unchecked Sendable {
    enum Kind: Sendable {
        case folder
        case file
        /// A bundle Finder shows as one file, such as an app.
        case package
        case symlink
    }

    let name: String
    let kind: Kind
    let identity: FileIdentity?
    private(set) weak var parent: SizeNode?
    /// Where the node lives when it cannot be derived from its parent: the
    /// scanned folder, or a node cut out of the tree.
    private var rootURL: URL?
    private(set) var children: [SizeNode] = []
    /// Space of items too small to keep as nodes.
    private(set) var prunedBytes: Int64 = 0
    private(set) var prunedCount = 0
    private(set) var bytes: Int64
    /// The folder, or part of it, could not be read.
    var isAccessDenied = false
    /// This item, or something inside it, is another name of data counted
    /// elsewhere in the tree. Kept even though it adds no bytes.
    var holdsSharedLink = false

    var id: ObjectIdentifier { ObjectIdentifier(self) }

    init(name: String, kind: Kind, identity: FileIdentity?, bytes: Int64 = 0, rootURL: URL? = nil) {
        self.name = name
        self.kind = kind
        self.identity = identity
        self.bytes = bytes
        self.rootURL = rootURL
    }

    /// The absolute location. Nodes cut out of the tree keep the location they
    /// had, so their children still resolve to real paths.
    var url: URL {
        if let rootURL { return rootURL }
        guard let parent else { return URL(fileURLWithPath: "/").appendingPathComponent(name) }
        return parent.url.appendingPathComponent(name, isDirectory: kind == .folder)
    }

    var isFolder: Bool { kind == .folder }

    /// A folder that could not be read at all: nothing inside it is known, so
    /// there is nothing meaningful to select.
    var isLocked: Bool {
        isAccessDenied && children.isEmpty && prunedCount == 0 && bytes == 0
    }

    var ancestors: [SizeNode] {
        var chain: [SizeNode] = []
        var current = parent
        while let node = current {
            chain.insert(node, at: 0)
            current = node.parent
        }
        return chain
    }

    // MARK: - Building

    func addChild(_ child: SizeNode) {
        child.parent = self
        children.append(child)
    }

    func addPruned(bytes: Int64, count: Int) {
        prunedBytes += bytes
        prunedCount += count
    }

    /// Totals the folder from its children and sorts them, largest first.
    func finish() {
        children.sort { $0.bytes > $1.bytes }
        bytes = children.reduce(prunedBytes) { $0 + $1.bytes }
    }

    // MARK: - Editing

    /// Detaches a removed child and subtracts its size from every ancestor.
    func remove(_ child: SizeNode) {
        guard let index = children.firstIndex(where: { $0 === child }) else { return }
        children.remove(at: index)
        var node: SizeNode? = self
        while let current = node {
            current.bytes -= child.bytes
            node = current.parent
        }
        child.rootURL = child.url
        child.parent = nil
    }

    /// Whether following parents from this node ends at `root`.
    func isInside(_ root: SizeNode) -> Bool {
        var node: SizeNode? = self
        while let current = node {
            if current === root { return true }
            node = current.parent
        }
        return false
    }
}
