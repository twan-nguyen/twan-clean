import XCTest
@testable import TwanClean

final class OrphanFinderTests: XCTestCase {
    private var tree: TemporaryTree!
    private var home: FakeHome!
    private var finder: OrphanFinder!
    private let installed = [makeApp(name: "Photo Editor", bundleIdentifier: "com.example.photoeditor", team: nil),
                             makeApp(name: "Google Chrome", bundleIdentifier: "com.google.Chrome", team: nil)]

    override func setUpWithError() throws {
        tree = try TemporaryTree()
        home = try FakeHome(tree: tree)
        try tree.makeDirectory("home/Library/Logs")
        finder = OrphanFinder(policy: home.policy, searchFolders: [home.url("Library/Caches"), home.url("Library/Logs"),
                                                                   home.url("Library/Preferences")],
                              isRegistered: { _ in false })
        try tree.makeFile("home/Library/Caches/com.example.photoeditor/cache.db", bytes: 8_192)
        try tree.makeFile("home/Library/Caches/Google/blob", bytes: 8_192)
        try tree.makeFile("home/Library/Caches/com.apple.Safari/cache.db", bytes: 8_192)
        try tree.makeFile("home/Library/Caches/Homebrew/x.tar.gz", bytes: 8_192)
        try tree.makeFile("home/Library/Caches/com.oldvendor.removedapp/cache.db", bytes: 8_192)
        try tree.makeFile("home/Library/Logs/OldTool/run.log", bytes: 8_192)
        try tree.makeFile("home/Library/Preferences/com.oldvendor.removedapp.plist", bytes: 8_192)
    }

    override func tearDown() {
        finder = nil
        home = nil
        tree = nil
    }

    private func names(running: Set<String> = [], ignored: Set<String> = []) throws -> Set<String> {
        Set(try finder.find(installed: installed, runningBundleIDs: running, ignored: ignored).map(\.name))
    }

    func testTheScanReportsWhereItIsReading() throws {
        let reporter = ScanProgressReporter()

        let found = try finder.find(installed: installed, runningBundleIDs: [], ignored: [], progress: reporter)

        // The last thing read is an item measured, and every orphan was measured.
        let path = try XCTUnwrap(reporter.currentPath)
        XCTAssertTrue(path.hasPrefix(tree.root.path), path)
        XCTAssertFalse(found.isEmpty)
    }

    func testReportsOnlyFilesOfAppsThatAreGone() throws {
        XCTAssertEqual(try names(), ["com.oldvendor.removedapp", "OldTool"])
    }

    func testNeverOffersPreferencesEvenIfTheirAppIsGone() throws {
        XCTAssertFalse(try names().contains("com.oldvendor.removedapp.plist"))
    }

    func testRunningAppsCountAsInstalled() throws {
        XCTAssertFalse(try names(running: ["com.oldvendor.removedapp"]).contains("com.oldvendor.removedapp"))
    }

    func testIgnoredItemsAreLeftOut() throws {
        let ignored = home.url("Library/Logs/OldTool").path
        XCTAssertFalse(try names(ignored: [ignored]).contains("OldTool"))
    }

    func testOrphansGoToTheTrash() throws {
        let item = try XCTUnwrap(try finder.find(installed: installed, runningBundleIDs: [], ignored: []).first)
        XCTAssertEqual(item.removalRequest.purpose, .orphan)
        XCTAssertEqual(RemovalPurpose.orphan.mode, .trash)
    }

    func testIgnoreStoreRoundTrips() throws {
        let store = OrphanIgnoreStore(file: tree.url("ignore/orphans.json"))
        XCTAssertTrue(store.load().isEmpty)
        try store.save(["/a", "/b"])
        XCTAssertEqual(store.load(), ["/a", "/b"])
    }
}
