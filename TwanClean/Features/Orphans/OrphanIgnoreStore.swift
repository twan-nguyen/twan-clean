import Foundation

/// Paths the user chose to always ignore in the orphan list.
struct OrphanIgnoreStore: Sendable {
    /// What loading found.
    struct Loaded: Sendable {
        var paths: Set<String> = []
        /// Set when the file existed but could not be read. The list starts
        /// empty then, and `backup` is where the unreadable file was kept
        /// (nil if it could not be moved) so the next save does not destroy it.
        var wasUnreadable = false
        var backup: URL?
    }

    let file: URL

    init(file: URL = OrphanIgnoreStore.defaultFile) {
        self.file = file
    }

    static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TwanClean/orphan-ignore.json")
    }

    func load() -> Set<String> {
        loadReportingDamage().paths
    }

    /// Like `load()`, but moves an unreadable file aside instead of leaving it
    /// to be overwritten by the next save.
    func loadReportingDamage() -> Loaded {
        guard FileIdentity.of(file) != nil else { return Loaded() }
        if let data = try? Data(contentsOf: file), let paths = try? JSONDecoder().decode([String].self, from: data) {
            return Loaded(paths: Set(paths))
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = file.deletingLastPathComponent()
            .appendingPathComponent("\(file.deletingPathExtension().lastPathComponent)-unreadable-\(stamp).json")
        let moved = (try? FileManager.default.moveItem(at: file, to: backup)) != nil
        return Loaded(wasUnreadable: true, backup: moved ? backup : nil)
    }

    func save(_ paths: Set<String>) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(paths.sorted()).write(to: file, options: .atomic)
    }
}
