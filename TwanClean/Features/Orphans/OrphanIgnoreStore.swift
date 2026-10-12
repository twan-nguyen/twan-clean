import Foundation

/// Paths the user chose to always ignore in the orphan list.
struct OrphanIgnoreStore: Sendable {
    let file: URL

    init(file: URL = OrphanIgnoreStore.defaultFile) {
        self.file = file
    }

    static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TwanClean/orphan-ignore.json")
    }

    func load() -> Set<String> {
        guard let data = try? Data(contentsOf: file),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(paths)
    }

    func save(_ paths: Set<String>) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(paths.sorted()).write(to: file, options: .atomic)
    }
}
