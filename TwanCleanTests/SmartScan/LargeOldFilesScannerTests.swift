import XCTest
@testable import TwanClean

final class LargeOldFilesScannerTests: XCTestCase {
    private var tree: TemporaryTree!
    private var home: FakeHome!
    private let now = Date()

    override func setUpWithError() throws {
        tree = try TemporaryTree()
        home = try FakeHome(tree: tree)
    }

    override func tearDown() {
        home = nil
        tree = nil
    }

    private func age(_ url: URL, days: Double) throws {
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-days * 86_400)],
                                              ofItemAtPath: url.path)
    }

    private func scan(excluding excluded: [String] = []) async throws -> [String: CleanableItem] {
        var settings = ScanSettings()
        settings.largeFileMinimumBytes = 200_000
        settings.oldFileMonths = 6
        settings.oldFileMinimumBytes = 50_000
        settings.excludedFolders = excluded
        let result = try await LargeOldFilesScanner().scan(home.scanContext(settings: settings, now: now))
        return Dictionary(uniqueKeysWithValues: result.items.map { ($0.name, $0) })
    }

    func testFindsLargeAndOldFilesOnly() async throws {
        try tree.makeFile("home/Downloads/big.dmg", bytes: 300_000)
        try age(try tree.makeFile("home/Documents/old.pdf", bytes: 80_000), days: 400)
        try age(try tree.makeFile("home/Desktop/old-but-small.txt", bytes: 1_000), days: 400)
        try tree.makeFile("home/Documents/recent-medium.key", bytes: 80_000)

        let items = try await scan()

        XCTAssertEqual(Set(items.keys), ["big.dmg", "old.pdf"])
    }

    func testNothingIsPreselectedAndEverythingGoesToTheTrash() async throws {
        try tree.makeFile("home/Downloads/big.dmg", bytes: 300_000)
        let items = try await scan()
        XCTAssertEqual(items["big.dmg"]?.selectedByDefault, false)
        XCTAssertEqual(items["big.dmg"]?.purpose, .userFile)
        XCTAssertEqual(items["big.dmg"]?.purpose.mode, .trash)
    }

    func testPackagesAreJudgedAsOneItem() async throws {
        try tree.makeFile("home/Downloads/Tool.app/Contents/MacOS/tool", bytes: 150_000)
        try tree.makeFile("home/Downloads/Tool.app/Contents/Resources/data", bytes: 150_000)

        let items = try await scan()

        XCTAssertNotNil(items["Tool.app"])
        XCTAssertNil(items["tool"])
    }

    func testExcludedFoldersAreSkipped() async throws {
        let excluded = try tree.makeDirectory("home/Documents/VMs")
        try tree.makeFile("home/Documents/VMs/disk.img", bytes: 300_000)

        let items = try await scan(excluding: [excluded.path])

        XCTAssertNil(items["disk.img"])
    }
}
