import XCTest
@testable import TwanClean

final class CoordinatorTests: XCTestCase {
    private func ids(_ results: [CategoryResult], _ category: CleanupCategoryID) -> [String] {
        results.first { $0.category == category }?.items.map(\.id) ?? []
    }

    func testSamePathIsKeptByTheOwningCategoryOnly() {
        let path = "/Users/me/Library/Caches/com.apple.dt.Xcode"
        let resolved = SmartScanCoordinator.resolveOverlaps([
            CategoryResult(category: .userCache, items: [makeItem(path, .userCache)]),
            CategoryResult(category: .xcode, items: [makeItem(path, .xcode)]),
        ])
        XCTAssertEqual(ids(resolved, .xcode), [path])
        XCTAssertEqual(ids(resolved, .userCache), [])
    }

    func testItemInsideAnOwnedFolderIsDropped() {
        let resolved = SmartScanCoordinator.resolveOverlaps([
            CategoryResult(category: .userCache, items: [makeItem("/h/Library/Caches/Yarn/v6/pkg", .userCache)]),
            CategoryResult(category: .node, items: [makeItem("/h/Library/Caches/Yarn", .node)]),
        ])
        XCTAssertEqual(ids(resolved, .userCache), [])
    }

    func testFolderContainingAnOwnedItemIsDropped() {
        let resolved = SmartScanCoordinator.resolveOverlaps([
            CategoryResult(category: .userCache, items: [makeItem("/h/.cache", .userCache)]),
            CategoryResult(category: .node, items: [makeItem("/h/.cache/pnpm", .node)]),
        ])
        XCTAssertEqual(ids(resolved, .userCache), [])
        XCTAssertEqual(ids(resolved, .node), ["/h/.cache/pnpm"])
    }

    func testUnrelatedItemsSurvive() {
        let resolved = SmartScanCoordinator.resolveOverlaps([
            CategoryResult(category: .userCache, items: [makeItem("/h/Library/Caches/a", .userCache)]),
            CategoryResult(category: .xcode, items: [makeItem("/h/Library/Caches/ab", .xcode)]),
        ])
        XCTAssertEqual(ids(resolved, .userCache), ["/h/Library/Caches/a"])
        XCTAssertEqual(ids(resolved, .xcode), ["/h/Library/Caches/ab"])
    }

    func testScanRunsEveryRequestedCategoryWithinTheConcurrencyLimit() async throws {
        let tracker = ConcurrencyTracker()
        let scanners = CleanupCategoryID.allCases.map { StubScanner(category: $0, tracker: tracker) }
        let coordinator = SmartScanCoordinator(scanners: scanners, maximumConcurrentScans: 3)
        let tree = try TemporaryTree()
        let home = try FakeHome(tree: tree)

        let results = try await coordinator.scan(CleanupCategoryID.allCases, context: home.scanContext())

        XCTAssertEqual(Set(results.map(\.category)), Set(CleanupCategoryID.allCases))
        XCTAssertLessThanOrEqual(tracker.peak, 3)
    }
}

private final class ConcurrencyTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var running = 0
    private(set) var peak = 0

    func enter() {
        lock.lock(); running += 1; peak = max(peak, running); lock.unlock()
    }

    func leave() {
        lock.lock(); running -= 1; lock.unlock()
    }
}

private struct StubScanner: CategoryScanner {
    let category: CleanupCategoryID
    let tracker: ConcurrencyTracker

    func scan(_ context: ScanContext) async throws -> CategoryResult {
        tracker.enter()
        try await Task.sleep(nanoseconds: 20_000_000)
        tracker.leave()
        return CategoryResult(category: category, items: [makeItem("/stub/\(category.rawValue)", category)])
    }
}
