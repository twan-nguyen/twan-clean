import XCTest
@testable import TwanClean

final class XcodeJunkScannerTests: XCTestCase {
    private var tree: TemporaryTree!
    private var home: FakeHome!

    override func setUpWithError() throws {
        tree = try TemporaryTree()
        home = try FakeHome(tree: tree)
        try tree.makeFile("home/Library/Caches/com.apple.dt.Xcode/cache.db", bytes: 8_192)
        try tree.makeFile("home/Library/Developer/Xcode/DerivedData/App-abc/Build/out.o", bytes: 8_192)
        try tree.makeFile("home/Library/Developer/Xcode/Archives/2026-10-13/App.xcarchive/Info.plist", bytes: 8_192)
    }

    override func tearDown() {
        home = nil
        tree = nil
    }

    private func scan(apps: [RunningApp] = []) async throws -> [String: CleanableItem] {
        let result = try await XcodeJunkScanner().scan(home.scanContext(runningApps: apps))
        return Dictionary(uniqueKeysWithValues: result.items.map { ($0.name, $0) })
    }

    func testXcodeCacheIsPreselectedAndNotMarkedAsMacOS() async throws {
        let items = try await scan()
        let cache = try XCTUnwrap(items["com.apple.dt.Xcode"])
        XCTAssertTrue(cache.selectedByDefault)
        XCTAssertFalse(cache.notes.contains(.usedByMacOS))
    }

    func testOtherAppleCachesAreStillMarkedAsMacOS() async throws {
        try tree.makeFile("home/Library/Caches/com.apple.Safari/cache.db", bytes: 8_192)
        let result = try await UserCacheScanner().scan(home.scanContext())
        let safari = try XCTUnwrap(result.items.first { $0.name == "com.apple.Safari" })
        XCTAssertTrue(safari.notes.contains(.usedByMacOS))
        XCTAssertFalse(safari.selectedByDefault)
    }

    func testNothingIsPreselectedWhileXcodeRuns() async throws {
        let items = try await scan(apps: [RunningApp(bundleID: "com.apple.dt.Xcode", name: "Xcode")])
        XCTAssertEqual(items["com.apple.dt.Xcode"]?.selectedByDefault, false)
        XCTAssertEqual(items["App-abc"]?.selectedByDefault, false)
        XCTAssertTrue(items["App-abc"]?.notes.contains(.appIsRunning) ?? false)
    }

    func testBuildProductsArePreselectedWhenXcodeIsClosed() async throws {
        let items = try await scan()
        XCTAssertEqual(items["App-abc"]?.selectedByDefault, true)
    }

    func testArchivesAreNeverPreselected() async throws {
        let items = try await scan()
        XCTAssertEqual(items["2026-10-13"]?.selectedByDefault, false)
    }
}
