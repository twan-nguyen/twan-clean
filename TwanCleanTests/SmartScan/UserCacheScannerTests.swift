import XCTest
@testable import TwanClean

final class UserCacheScannerTests: XCTestCase {
    private var tree: TemporaryTree!
    private var home: FakeHome!

    override func setUpWithError() throws {
        tree = try TemporaryTree()
        home = try FakeHome(tree: tree)
        try tree.makeFile("home/Library/Caches/com.example.editor/cache.db", bytes: 8_192)
        try tree.makeFile("home/Library/Caches/com.example.player/blob", bytes: 8_192)
        try tree.makeFile("home/Library/Caches/com.apple.Safari/cache.db", bytes: 8_192)
        try tree.makeFile("home/Library/Caches/Homebrew/downloads/x.tar.gz", bytes: 8_192)
        try tree.makeFile("home/.cache/pip/wheel", bytes: 8_192)
        try tree.makeDirectory("home/Library/Caches/com.example.empty")
    }

    override func tearDown() {
        home = nil
        tree = nil
    }

    private func scan(running: Set<String> = []) async throws -> [String: CleanableItem] {
        let result = try await UserCacheScanner().scan(home.scanContext(running: running))
        return Dictionary(uniqueKeysWithValues: result.items.map { ($0.name, $0) })
    }

    func testFindsCacheFoldersDynamically() async throws {
        let items = try await scan()
        XCTAssertNotNil(items["com.example.editor"])
        XCTAssertNotNil(items["pip"])
        XCTAssertEqual(items["com.example.editor"]?.purpose, .regenerableCache)
        XCTAssertEqual(items["com.example.editor"]?.selectedByDefault, true)
    }

    func testLeavesClaimedAndEmptyFoldersOut() async throws {
        let items = try await scan()
        XCTAssertNil(items["Homebrew"])
        XCTAssertNil(items["com.example.empty"])
    }

    func testDoesNotPreselectCachesOfRunningAppsOrMacOS() async throws {
        let items = try await scan(running: ["com.example.Player"])
        XCTAssertEqual(items["com.example.player"]?.selectedByDefault, false)
        XCTAssertTrue(items["com.example.player"]?.notes.contains(.appIsRunning) ?? false)
        XCTAssertEqual(items["com.apple.Safari"]?.selectedByDefault, false)
    }

    func testSizesAreAllocatedBytes() async throws {
        let items = try await scan()
        XCTAssertGreaterThanOrEqual(items["com.example.editor"]?.bytes ?? 0, 8_192)
    }
}
