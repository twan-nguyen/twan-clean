import XCTest
@testable import TwanClean

/// What counts as installed when deciding that a file is left over, and what
/// the scan does when it cannot tell.
final class OrphanKnownAppsTests: XCTestCase {
    private var tree: TemporaryTree!
    private var home: FakeHome!
    private let editor = makeApp(name: "Photo Editor", bundleIdentifier: "com.example.photoeditor", team: nil)

    override func setUpWithError() throws {
        tree = try TemporaryTree()
        home = try FakeHome(tree: tree)
        try tree.makeDirectory("home/Library/Logs")
    }

    override func tearDown() {
        home = nil
        tree = nil
    }

    /// A folder standing in for /Library/Logs, which the real policy allows
    /// but a test tree cannot contain.
    private var sharedLogs: URL { home.url("Library/Saved Application State") }

    private func finder(registered: @escaping @Sendable (String) -> Bool = { _ in false }) -> OrphanFinder {
        OrphanFinder(policy: home.policy,
                     searchFolders: [home.url("Library/Caches"), home.url("Library/Logs"), sharedLogs],
                     bundleIdentifierOnlyFolders: [sharedLogs.path], isRegistered: registered)
    }

    private func names(_ finder: OrphanFinder, installed: [InstalledApp]? = nil,
                       extraIdentifiers: Set<String> = []) throws -> Set<String> {
        Set(try finder.find(installed: installed ?? [editor], runningBundleIDs: [], ignored: [],
                            extraIdentifiers: extraIdentifiers).map(\.name))
    }

    // MARK: - Installed outside the usual places

    func testAppsRegisteredWithLaunchServicesAreNotOrphaned() throws {
        try tree.makeFile("home/Library/Caches/com.oldvendor.removedapp/cache.db", bytes: 4_096)
        try tree.makeFile("home/Library/Caches/com.oldvendor.gone/cache.db", bytes: 4_096)

        let found = try names(finder(registered: { $0 == "com.oldvendor.removedapp" }))

        XCTAssertEqual(found, ["com.oldvendor.gone"])
    }

    func testFilesNamedAfterAnIdentifierExtendingARegisteredOneAreNotOrphaned() throws {
        try tree.makeFile("home/Library/Caches/com.oldvendor.removedapp.helper/cache.db", bytes: 4_096)
        try tree.makeFile("home/Library/Caches/com.oldvendor.removedapp.helper.savedState/state", bytes: 4_096)

        XCTAssertTrue(try names(finder(registered: { $0 == "com.oldvendor.removedapp" })).isEmpty)
        XCTAssertEqual(try names(finder()).count, 2)
    }

    func testHelperAppsAndLaunchdLabelsInsideAppsCountAsInstalled() throws {
        try tree.makeFile("home/Library/Caches/com.helperco.loginhelper.cache/cache.db", bytes: 4_096)
        try tree.makeFile("home/Library/Caches/com.daemonco.daemon.cache/cache.db", bytes: 4_096)
        try tree.makeFile("home/Library/Caches/com.goneco.removedapp.cache/cache.db", bytes: 4_096)
        let helper = makeApp(name: "Login Helper", bundleIdentifier: "com.helperco.loginhelper", team: nil)

        XCTAssertEqual(try names(finder()).count, 3, "unknown without them")
        let found = try names(finder(), installed: [editor, helper], extraIdentifiers: ["com.daemonco.daemon"])

        XCTAssertEqual(found, ["com.goneco.removedapp.cache"])
    }

    func testFilesNamedAfterAnInstalledAppAndThenSomethingElseAreNotOrphaned() throws {
        let warp = makeApp(name: "Warp", bundleIdentifier: "dev.warp.Warp-Stable", team: nil)
        try tree.makeFile("home/Library/Logs/warp.log.old.0", bytes: 4_096)
        try tree.makeFile("home/Library/Logs/Zalo_2026-01-01", bytes: 4_096)
        try tree.makeFile("home/Library/Logs/OldTool_2026-01-01", bytes: 4_096)
        let zalo = makeApp(name: "Zalo", bundleIdentifier: "com.vng.zalo", team: nil)

        XCTAssertEqual(try names(finder(), installed: [editor, warp, zalo]), ["OldTool_2026-01-01"])
    }

    // MARK: - macOS's own logs

    func testMacOSLogsInTheSharedLogFolderAreNeverReported() throws {
        for name in ["WindowServer", "Xsan", "DiagnosticReports", "hidfw-crashlogs", "MCXTools.log", "LKDC-setup.log"] {
            try tree.makeFile("home/Library/Saved Application State/\(name)/entry", bytes: 4_096)
        }
        try tree.makeFile("home/Library/Saved Application State/com.oldvendor.removedapp/entry", bytes: 4_096)
        try tree.makeFile("home/Library/Saved Application State/PlainThirdPartyTool/entry", bytes: 4_096)

        XCTAssertEqual(try names(finder()), ["com.oldvendor.removedapp"])
    }

    func testTheSkipListNamesMacOSLogsOnItsOwn() {
        for name in ["WindowServer", "Xsan", "DiagnosticReports", "hidfw-crashlogs", "MCXTools.log", "LKDC-setup.log"] {
            XCTAssertTrue(OrphanSkipList.contains(name), name)
        }
    }

    func testTheSkipListUnderstandsReverseDomainNames() {
        XCTAssertTrue(OrphanSkipList.contains("org.swift.swiftpm"))
        XCTAssertTrue(OrphanSkipList.contains("com.google.Keystone.Agent"))
        XCTAssertTrue(OrphanSkipList.contains("com.apple.Safari"))
        XCTAssertFalse(OrphanSkipList.contains("com.oldvendor.removedapp"))
        // "go" is on the list, but a short entry never hides a reverse-domain name.
        XCTAssertFalse(OrphanSkipList.contains("com.oldvendor.goapp"))
    }

    // MARK: - When the list of apps cannot be trusted

    func testAnEmptyAppListIsRefusedRatherThanReportingEverything() throws {
        try tree.makeFile("home/Library/Caches/com.oldvendor.removedapp/cache.db", bytes: 4_096)
        XCTAssertThrowsError(try finder().find(installed: [], runningBundleIDs: [], ignored: [])) { error in
            XCTAssertTrue(error is OrphanFinder.ScanError)
        }
    }

    // MARK: - Ignore list

    func testAnUnreadableIgnoreListIsKeptAsABackupNotOverwritten() throws {
        let file = tree.url("ignore/orphans.json")
        try tree.makeDirectory("ignore")
        try Data("{ not json".utf8).write(to: file)
        let store = OrphanIgnoreStore(file: file)

        let loaded = store.loadReportingDamage()

        XCTAssertTrue(loaded.wasUnreadable)
        XCTAssertTrue(loaded.paths.isEmpty)
        let backup = try XCTUnwrap(loaded.backup)
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "{ not json")
        XCTAssertFalse(tree.exists(file))
        try store.save(["/a"])
        XCTAssertEqual(store.load(), ["/a"])
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "{ not json", "the backup survives a save")
    }

    func testAMissingIgnoreListIsNotDamage() {
        let loaded = OrphanIgnoreStore(file: tree.url("none/orphans.json")).loadReportingDamage()
        XCTAssertFalse(loaded.wasUnreadable)
        XCTAssertNil(loaded.backup)
    }
}

@MainActor
final class OrphansViewModelTests: XCTestCase {
    private var tree: TemporaryTree!
    private var home: FakeHome!

    override func setUpWithError() throws {
        tree = try TemporaryTree()
        home = try FakeHome(tree: tree)
        try tree.makeFile("home/Library/Caches/com.oldvendor.removedapp/cache.db", bytes: 4_096)
    }

    override func tearDown() {
        home = nil
        tree = nil
    }

    private func makeModel(applications: String = "Applications", store: OrphanIgnoreStore? = nil) throws -> OrphansViewModel {
        let home = home!
        return OrphansViewModel(
            index: InstalledAppIndex(roots: [tree.url(applications)]),
            makeFinder: {
                OrphanFinder(policy: home.policy, searchFolders: [home.url("Library/Caches")], isRegistered: { _ in false })
            },
            ignoreStore: store ?? OrphanIgnoreStore(file: tree.url("ignore/orphans.json")),
            removal: try home.removalService(), runningBundleIDs: { [] })
    }

    func testAScanWithAnUnreadableAppListShowsAnErrorNotAnEmptyResult() async throws {
        try tree.makeDirectory("Empty")
        let model = try makeModel(applications: "Empty")

        await model.scan()?.value

        XCTAssertNotNil(model.scanError)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(model.phase, .ready)
    }

    func testAScanWithAnAppListFindsTheLeftovers() async throws {
        try tree.makeAppBundle("Applications/Editor.app", bundleIdentifier: "com.example.editor")
        let model = try makeModel()

        await model.scan()?.value

        XCTAssertNil(model.scanError)
        XCTAssertEqual(model.items.map(\.name), ["com.oldvendor.removedapp"])
    }

    private func scannedAndSelected() async throws -> OrphansViewModel {
        try tree.makeAppBundle("Applications/Editor.app", bundleIdentifier: "com.example.editor")
        let model = try makeModel()
        await model.scan()?.value
        model.selection = Set(model.items.map(\.id))
        return model
    }

    func testScanningRecordsWhenItStartedAndWhereItIsReading() async throws {
        try tree.makeAppBundle("Applications/Editor.app", bundleIdentifier: "com.example.editor")
        let model = try makeModel()
        XCTAssertNil(model.scanStarted)

        await model.scan()?.value

        XCTAssertNotNil(model.scanStarted)
        XCTAssertNotNil(model.scanProgress.currentPath)
    }

    func testRemovingPublishesItsProgressAndClearsItWhenDone() async throws {
        let model = try await scannedAndSelected()
        let log = RemovalProgressLog(model.$removalProgress)

        await model.trashSelection()

        XCTAssertEqual(log.shown.first?.stage, .movingToTrash)
        XCTAssertEqual(log.shown.first?.total, 1)
        XCTAssertNil(model.removalProgress)
        XCTAssertTrue(log.endedEmpty)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertTrue(model.items.isEmpty)
    }

    func testACancelledRemovalStillClearsItsProgress() async throws {
        let model = try await scannedAndSelected()

        let removing = Task { await model.trashSelection() }
        removing.cancel()
        await removing.value

        XCTAssertNil(model.removalProgress)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.items.count, 1, "nothing was removed")
        XCTAssertTrue(tree.exists(home.url("Library/Caches/com.oldvendor.removedapp")))
    }

    func testFailingToSaveTheIgnoreListIsReported() async throws {
        try tree.makeAppBundle("Applications/Editor.app", bundleIdentifier: "com.example.editor")
        // The store's folder cannot be created: a file is in its way.
        try tree.makeFile("blocked")
        let model = try makeModel(store: OrphanIgnoreStore(file: tree.url("blocked/orphans.json")))
        await model.scan()?.value
        let item = try XCTUnwrap(model.items.first)

        model.ignore(item)

        XCTAssertNotNil(model.notice)
        XCTAssertTrue(model.items.isEmpty)
    }

    func testAnUnreadableIgnoreListIsReportedWhenTheModelStarts() throws {
        try tree.makeFile("ignore/orphans.json")
        try Data("nope".utf8).write(to: tree.url("ignore/orphans.json"))

        let model = try makeModel()

        XCTAssertNotNil(model.notice)
        XCTAssertTrue(model.ignored.isEmpty)
    }
}
