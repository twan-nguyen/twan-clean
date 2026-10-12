import Foundation

/// Runs the category scanners a few at a time and settles items that more
/// than one category found.
struct SmartScanCoordinator: Sendable {
    let scanners: [CleanupCategoryID: any CategoryScanner]
    let maximumConcurrentScans: Int

    init(scanners: [any CategoryScanner] = Self.standardScanners, maximumConcurrentScans: Int = 3) {
        self.scanners = Dictionary(uniqueKeysWithValues: scanners.map { ($0.category, $0) })
        self.maximumConcurrentScans = maximumConcurrentScans
    }

    static let standardScanners: [any CategoryScanner] = [
        SystemJunkScanner(), UserCacheScanner(), AIAppsScanner(), MailAttachmentsScanner(), TrashScanner(),
        LargeOldFilesScanner(), XcodeJunkScanner(), HomebrewCacheScanner(), NodeCacheScanner(), DockerCacheScanner(),
    ]

    /// Scans the given categories. `onCategoryFinished` is called as each
    /// category completes, for progress only; the returned results are final.
    func scan(_ categories: [CleanupCategoryID], context: ScanContext,
              onCategoryFinished: @escaping @Sendable (CleanupCategoryID) async -> Void = { _ in })
        async throws -> [CategoryResult] {
        // Heavy categories first, so a long walk is not left for the end.
        let ordered = categories.filter { scanners[$0] != nil }.sorted { $0.isHeavy && !$1.isHeavy }

        let results = try await withThrowingTaskGroup(of: CategoryResult.self) { group in
            var pending = ordered.makeIterator()
            func startNext() {
                guard let category = pending.next(), let scanner = scanners[category] else { return }
                group.addTask {
                    let result = try await scanner.scan(context)
                    await onCategoryFinished(category)
                    return result
                }
            }
            for _ in 0..<maximumConcurrentScans { startNext() }

            var collected: [CategoryResult] = []
            while let result = try await group.next() {
                collected.append(result)
                startNext()
            }
            return collected
        }
        return Self.resolveOverlaps(results)
    }

    /// Gives every folder to one category only. Categories earlier in
    /// `CleanupCategoryID.ownershipOrder` keep an item; a later category loses
    /// any item equal to, inside, or containing one already kept, so no space
    /// is counted twice.
    static func resolveOverlaps(_ results: [CategoryResult]) -> [CategoryResult] {
        let rank = Dictionary(uniqueKeysWithValues: CleanupCategoryID.ownershipOrder.enumerated().map { ($1, $0) })
        var keptPaths = Set<String>()
        var keptAncestors = Set<String>()
        var resolved: [CategoryResult] = []
        for var result in results.sorted(by: { rank[$0.category, default: .max] < rank[$1.category, default: .max] }) {
            result.items.removeAll { item in
                let path = item.id.lowercased()
                return keptPaths.contains(path)
                    || keptAncestors.contains(path)
                    || ancestors(of: path).contains { keptPaths.contains($0) }
            }
            for item in result.items {
                let path = item.id.lowercased()
                keptPaths.insert(path)
                keptAncestors.formUnion(ancestors(of: path))
            }
            resolved.append(result)
        }
        return resolved
    }

    /// "/a/b/c" gives "/a/b" and "/a".
    private static func ancestors(of path: String) -> [String] {
        var result: [String] = []
        var current = (path as NSString).deletingLastPathComponent
        while current.count > 1 {
            result.append(current)
            current = (current as NSString).deletingLastPathComponent
        }
        return result
    }
}
