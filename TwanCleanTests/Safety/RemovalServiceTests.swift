import XCTest
@testable import TwanClean

final class RemovalServiceTests: XCTestCase {
    private var tree: TemporaryTree!
    private var home: FakeHome!
    private var service: RemovalService!

    override func setUpWithError() throws {
        tree = try TemporaryTree()
        home = try FakeHome(tree: tree)
        service = try home.removalService()
    }

    override func tearDown() {
        service = nil
        home = nil
        tree = nil
    }

    func testRegenerableCacheIsDeleted() async throws {
        let item = try tree.makeFile("home/Library/Caches/com.example/blob", bytes: 4096)
        let report = await service.remove([try home.request(item, .regenerableCache, bytes: 4096)])

        XCTAssertEqual(report.removed.count, 1)
        XCTAssertEqual(report.freedBytes, 4096)
        XCTAssertTrue(report.trashedLocations.isEmpty)
        XCTAssertFalse(tree.exists(item))
    }

    func testUserFileGoesToTheTrash() async throws {
        let item = try tree.makeFile("home/Downloads/movie.bin")
        let report = await service.remove([try home.request(item, .userFile)])

        XCTAssertEqual(report.removed.count, 1)
        XCTAssertFalse(tree.exists(item))
        XCTAssertEqual(report.trashedLocations.count, 1)
        XCTAssertTrue(report.trashedLocations.allSatisfy { FileIdentity.of($0) != nil })
    }

    func testRemovingSymlinkKeepsItsTarget() async throws {
        let target = try tree.makeFile("home/Documents/keep.txt")
        let link = try tree.makeSymlink("home/Library/Caches/link", to: target)

        let report = await service.remove([try home.request(link, .regenerableCache)])

        XCTAssertEqual(report.removed.count, 1)
        XCTAssertFalse(tree.exists(link))
        XCTAssertTrue(tree.exists(target))
    }

    func testDirectoryContainingSymlinkKeepsTheTarget() async throws {
        let target = try tree.makeFile("home/Documents/keep.txt")
        try tree.makeSymlink("home/Library/Caches/app/link", to: target)
        let folder = home.url("Library/Caches/app")

        _ = await service.remove([try home.request(folder, .regenerableCache)])

        XCTAssertFalse(tree.exists(folder))
        XCTAssertTrue(tree.exists(target))
    }

    func testItemReplacedSinceScanIsRefused() async throws {
        let item = try tree.makeFile("home/Library/Caches/swap")
        let request = try home.request(item, .regenerableCache)
        try FileManager.default.removeItem(at: item)
        try tree.makeFile("home/Library/Caches/padding")
        try tree.makeFile("home/Library/Caches/swap")

        let report = await service.remove([request])

        XCTAssertEqual(report.refused.map(\.reason), [.changedSinceScan])
        XCTAssertTrue(tree.exists(item))
    }

    func testItemOutsideAllowedAreaIsRefusedAndKept() async throws {
        let document = try tree.makeFile("home/Documents/report.pdf")
        let report = await service.remove([try home.request(document, .regenerableCache)])

        XCTAssertEqual(report.refused.map(\.reason), [.outsideAllowedArea])
        XCTAssertTrue(tree.exists(document))
    }

    func testMissingItemIsReportedAsAlreadyGone() async throws {
        let item = try tree.makeFile("home/Library/Caches/gone")
        let request = try home.request(item, .regenerableCache)
        try FileManager.default.removeItem(at: item)

        let report = await service.remove([request])

        XCTAssertEqual(report.alreadyGone.count, 1)
        XCTAssertEqual(report.freedBytes, 0)
    }

    func testTrashIsUsedOnlyForTrashPurposes() async throws {
        let cache = try tree.makeFile("home/Library/Caches/blob")
        let download = try tree.makeFile("home/Downloads/movie.bin")
        let report = await service.remove([try home.request(cache, .regenerableCache), try home.request(download, .userFile)])
        XCTAssertEqual(report.trashedLocations.map(\.lastPathComponent).filter { $0.hasSuffix("movie.bin") }.count, 1)
        XCTAssertFalse(report.trashedLocations.contains { $0.lastPathComponent.hasSuffix("blob") })
    }

    func testPermissionFailureAsksForAdministrator() async throws {
        let item = try tree.makeFile("home/Library/Caches/locked/file")
        let folder = item.deletingLastPathComponent()
        let request = try home.request(item, .regenerableCache)
        XCTAssertEqual(chmod(folder.path, 0o555), 0)
        defer { chmod(folder.path, 0o755) }

        let report = await service.remove([request])

        XCTAssertEqual(report.needsAdministrator.count, 1)
        XCTAssertTrue(tree.exists(item))
    }
}
