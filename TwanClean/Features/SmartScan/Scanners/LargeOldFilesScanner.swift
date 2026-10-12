import Foundation

struct LargeOldFilesScanner: CategoryScanner {
    let category = CleanupCategoryID.largeOld

    static let searchFolders = ["Downloads", "Documents", "Desktop"]

    /// Bundles that Finder shows as one file; they are judged as a whole.
    static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "photoslibrary", "fcpbundle", "logicx", "band",
        "pages", "numbers", "key", "rtfd", "xcarchive", "sparsebundle", "vmwarevm", "pvm", "utm",
    ]

    func scan(_ context: ScanContext) async throws -> CategoryResult {
        let settings = context.settings
        let oldCutoff = Calendar.current.date(byAdding: .month, value: -max(1, settings.oldFileMonths), to: context.now)
            ?? .distantPast
        // realpath, not standardizedFileURL: the latter drops "/private" and
        // would never match the paths the walk reports.
        let excluded = settings.excludedFolders.map { SafetyRules.canonicalPath($0) ?? $0 }

        func qualifies(bytes: Int64, modified: Date?) -> Bool {
            bytes >= settings.largeFileMinimumBytes
                || (bytes >= settings.oldFileMinimumBytes && (modified ?? context.now) < oldCutoff)
        }

        var candidates: [URL] = []
        var unreadable: [URL] = []
        for folder in Self.searchFolders {
            let root = context.homeURL(folder)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            guard !context.isProtected(root) else {
                unreadable.append(root)
                continue
            }
            try FileTreeWalker.walk(root) { entry in
                // macOS asks before an app may read Downloads, Documents or
                // Desktop; a refusal shows up as an unreadable root.
                if entry.depth == 0, entry.kind == .unreadableDirectory || entry.kind == .unreadable {
                    unreadable.append(root)
                    return .continue
                }
                if excluded.contains(where: { PathPolicy.isSame(entry.path, $0) || PathPolicy.isInside(entry.path, $0) }) {
                    return .skipDescendants
                }
                switch entry.kind {
                case .file:
                    if qualifies(bytes: entry.allocatedBytes, modified: entry.modificationDate) {
                        candidates.append(URL(fileURLWithPath: entry.path))
                    }
                case .directory where entry.depth > 0
                    && Self.packageExtensions.contains((entry.name as NSString).pathExtension.lowercased()):
                    candidates.append(URL(fileURLWithPath: entry.path))
                    return .skipDescendants
                default:
                    break
                }
                return .continue
            }
        }

        var builder = CategoryResultBuilder(category, context: context)
        unreadable.forEach { builder.noteUnreadable($0) }
        for url in candidates {
            try builder.add(url, purpose: .userFile, selected: false)
        }
        // Packages were collected regardless of size; drop those that do not
        // qualify once measured.
        var result = builder.finish()
        result.items.removeAll { !qualifies(bytes: $0.bytes, modified: $0.lastModified) }
        return result
    }
}
