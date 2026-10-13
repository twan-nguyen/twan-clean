import XCTest
@testable import TwanClean

final class LeftoverFinderTests: XCTestCase {
    private var tree: TemporaryTree!
    private var home: FakeHome!
    private var app: InstalledApp!

    override func setUpWithError() throws {
        tree = try TemporaryTree()
        home = try FakeHome(tree: tree)
        let bundle = try tree.makeAppBundle("home/Applications/Photo Editor.app",
                                            bundleIdentifier: "com.example.photoeditor", name: "Photo Editor")
        app = try XCTUnwrap(InstalledAppIndex.app(at: bundle))

        try tree.makeFile("home/Library/Application Support/Photo Editor/library.db", bytes: 8_192)
        try tree.makeFile("home/Library/Preferences/com.example.photoeditor.plist")
        try tree.makeFile("home/Library/Caches/com.example.photoeditor/cache.db", bytes: 8_192)
        try tree.makeFile("home/Library/Application Support/Example Inc/Photo Editor/settings.json")
        try tree.makeFile("home/Library/Application Support/Unrelated App/data")
        try tree.makeFile("home/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite")
        try tree.makeFile("home/Documents/Photo Editor Projects/holiday.edit")
        let container = try tree.makeDirectory("home/Library/Containers/3F2504E0-4F89-11D3-9A0C-0305E82C3301")
        try tree.makeFile("home/Library/Containers/3F2504E0-4F89-11D3-9A0C-0305E82C3301/Data/state")
        let metadata = try PropertyListSerialization.data(
            fromPropertyList: ["MCMMetadataIdentifier": "com.example.photoeditor"], format: .xml, options: 0)
        try metadata.write(to: container.appendingPathComponent(ContainerResolver.metadataFile))
    }

    override func tearDown() {
        app = nil
        home = nil
        tree = nil
    }

    func testTheSearchReportsWhereItIsReading() throws {
        let reporter = ScanProgressReporter()
        XCTAssertNil(reporter.currentPath)

        let scan = try LeftoverFinder(home: home.home, policy: home.policy, systemFolders: [])
            .find(for: app, sensitivity: .enhanced, progress: reporter)

        // The last thing read is one of the items being measured.
        let path = try XCTUnwrap(reporter.currentPath)
        XCTAssertTrue(scan.items.contains { $0.url.path == path || $0.url.path.hasPrefix(path) }, path)
        reporter.reset()
        XCTAssertNil(reporter.currentPath)
    }

    private func find(_ sensitivity: SearchSensitivity = .enhanced, protected: ProtectedLocations? = nil,
                      for target: InstalledApp? = nil, others: [InstalledApp] = []) throws -> LeftoverScan {
        try LeftoverFinder(home: home.home, policy: home.policy, protected: protected, systemFolders: [])
            .find(for: target ?? app, sensitivity: sensitivity, otherApps: others)
    }

    private func paths(_ scan: LeftoverScan) -> Set<String> {
        Set(scan.items.map { $0.url.path.replacingOccurrences(of: home.home.path + "/", with: "~/") })
    }

    func testFindsTheAppAndItsFiles() throws {
        let found = paths(try find())
        XCTAssertEqual(found, [
            "~/Applications/Photo Editor.app",
            "~/Library/Application Support/Photo Editor",
            "~/Library/Preferences/com.example.photoeditor.plist",
            "~/Library/Caches/com.example.photoeditor",
            "~/Library/Application Support/Example Inc/Photo Editor",
            "~/Library/Containers/3F2504E0-4F89-11D3-9A0C-0305E82C3301",
        ])
    }

    func testNeverLooksInDocumentsOrAtAppleData() throws {
        let found = paths(try find(.deep))
        XCTAssertFalse(found.contains { $0.hasPrefix("~/Documents") })
        XCTAssertFalse(found.contains { $0.contains("com.apple") })
        XCTAssertFalse(found.contains { $0.contains("Unrelated") })
    }

    func testAppGoesToTheTrashAsAnAppBundle() throws {
        let bundle = try XCTUnwrap(try find().items.first { $0.group == .application })
        XCTAssertEqual(bundle.purpose, .appBundle)
        XCTAssertTrue(bundle.selectedByDefault)
        XCTAssertTrue(try find().items.allSatisfy { $0.purpose.mode == .trash })
    }

    func testStrictModeFindsOnlyExactNames() throws {
        try tree.makeFile("home/Library/Caches/PhotoEditorHelper/blob")
        XCTAssertFalse(paths(try find(.strict)).contains("~/Library/Caches/PhotoEditorHelper"))
        XCTAssertTrue(paths(try find(.enhanced)).contains("~/Library/Caches/PhotoEditorHelper"))
    }

    func testDeveloperMatchesAreNeverPreselected() throws {
        try tree.makeFile("home/Library/Application Support/Example Shared/blob")
        let deep = try find(.deep).items.first { $0.name == "Example Shared" }
        XCTAssertEqual(deep?.tier, .developerName)
        XCTAssertEqual(deep?.selectedByDefault, false)
    }

    func testContainersAreSkippedAndReportedWithoutFullDiskAccess() throws {
        let scan = try find(protected: ProtectedLocations(home: home.home))
        XCTAssertFalse(paths(scan).contains { $0.hasPrefix("~/Library/Containers") })
        XCTAssertTrue(scan.lockedLocations.contains { $0.lastPathComponent == "Containers" })
    }

    func testFilesOfAnotherInstalledAppWithALongerNameAreLeftOut() throws {
        let notion = makeApp(name: "Notion", bundleIdentifier: "notion.id", team: nil)
        let calendar = makeApp(name: "Notion Calendar", bundleIdentifier: "com.cron.electron", team: nil)
        try tree.makeFile("home/Library/Application Support/Notion/state")
        try tree.makeFile("home/Library/Application Support/Notion Calendar/state")

        let found = paths(try find(for: notion, others: [notion, calendar]))

        XCTAssertTrue(found.contains("~/Library/Application Support/Notion"))
        XCTAssertFalse(found.contains("~/Library/Application Support/Notion Calendar"))
    }

    func testFilesClaimedEquallyByAnotherAppAreListedButNotSelected() throws {
        // Another app with the same name from a different developer.
        let twin = makeApp(name: "Photo Editor", bundleIdentifier: "com.other.editor", team: nil)
        try tree.makeFile("home/Library/Caches/PhotoEditorShared/blob")

        let item = try find(others: [twin]).items.first { $0.name == "PhotoEditorShared" }

        XCTAssertEqual(item?.mayBelongToAnotherApp, true)
        XCTAssertEqual(item?.selectedByDefault, false)
    }

    func testAppleAppsOnlyGetExactMatches() throws {
        let garageBand = makeApp(name: "GarageBand", bundleIdentifier: "com.apple.garageband10", team: nil)
        try tree.makeFile("home/Library/Application Support/GarageBand Loops/loop.caf")

        let found = paths(try find(.deep, for: garageBand))

        XCTAssertFalse(found.contains("~/Library/Application Support/GarageBand Loops"))
    }

    func testProtectedFoldersInsideApplicationSupportAreNotListed() throws {
        try tree.makeFile("home/Library/Application Support/AddressBook/Photo Editor contact.abcdp")
        let found = paths(try find(.deep, protected: ProtectedLocations(home: home.home)))
        XCTAssertFalse(found.contains { $0.contains("AddressBook") })
    }
}
