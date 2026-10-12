import XCTest
@testable import TwanClean

/// Without Full Disk Access the app must not read protected folders, so macOS
/// never interrupts the user with a permission prompt.
final class ProtectedLocationsTests: XCTestCase {
    private var tree: TemporaryTree!
    private var home: FakeHome!
    private var protected: ProtectedLocations!

    override func setUpWithError() throws {
        tree = try TemporaryTree()
        home = try FakeHome(tree: tree)
        protected = ProtectedLocations(home: home.home)
    }

    override func tearDown() {
        protected = nil
        home = nil
        tree = nil
    }

    func testRecognisesProtectedFolders() {
        XCTAssertTrue(protected.contains(home.url("Documents")))
        XCTAssertTrue(protected.contains(home.url("Downloads/file.zip")))
        XCTAssertTrue(protected.contains(home.url("Library/Containers/com.docker.docker/Data/log")))
        XCTAssertFalse(protected.contains(home.url("Library/Caches/com.example")))
        XCTAssertFalse(protected.contains(home.url("Library/Application Support/Example")))
    }

    func testFolderChosenInAnOpenPanelIsReadable() {
        let chosen = ProtectedLocations(home: home.home, consentedFolder: home.url("Documents"))
        XCTAssertFalse(chosen.contains(home.url("Documents/Projects")))
        XCTAssertTrue(chosen.contains(home.url("Downloads")))
    }

    func testLargeFileScanSkipsProtectedFoldersAndReportsThem() async throws {
        try tree.makeFile("home/Downloads/huge.iso", bytes: 300_000)
        var settings = ScanSettings()
        settings.largeFileMinimumBytes = 100_000
        let context = ScanContext(home: home.home, policy: home.policy,
                                  commands: CommandRunner(searchPaths: [], timeout: 1),
                                  settings: settings, protectedLocations: protected)

        let result = try await LargeOldFilesScanner().scan(context)

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertTrue(result.unreadableLocations.contains { $0.lastPathComponent == "Downloads" })
    }

    func testCacheScanSkipsOtherAppsContainers() async throws {
        try tree.makeFile("home/Library/Containers/com.docker.docker/Data/log/vm.log", bytes: 8_192)
        let context = ScanContext(home: home.home, policy: home.policy,
                                  commands: CommandRunner(searchPaths: [], timeout: 1), protectedLocations: protected)

        let result = try await DockerCacheScanner().scan(context)

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertFalse(result.unreadableLocations.isEmpty)
    }

    func testSpaceLensShowsProtectedFoldersAsLockedWithoutReadingThem() async throws {
        try tree.makeFile("home/Documents/report.pdf", bytes: 200_000)
        try tree.makeFile("home/Projects/app.zip", bytes: 200_000)

        let root = try await SizeTreeBuilder(minimumNodeBytes: 10_000).build(home.home, protected: protected)

        let documents = try XCTUnwrap(root.children.first { $0.name == "Documents" })
        XCTAssertTrue(documents.isAccessDenied)
        XCTAssertEqual(documents.bytes, 0)
        XCTAssertNotNil(root.children.first { $0.name == "Projects" })
    }

    func testSpaceLensReadsAProtectedFolderTheUserChose() async throws {
        try tree.makeFile("home/Documents/report.pdf", bytes: 200_000)
        let chosen = ProtectedLocations(home: home.home, consentedFolder: home.url("Documents"))

        let root = try await SizeTreeBuilder(minimumNodeBytes: 10_000).build(home.url("Documents"), protected: chosen)

        XCTAssertFalse(root.isAccessDenied)
        XCTAssertEqual(root.children.map(\.name), ["report.pdf"])
    }
}
