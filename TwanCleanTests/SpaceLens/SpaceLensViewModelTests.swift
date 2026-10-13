import XCTest
@testable import TwanClean

@MainActor
final class SpaceLensViewModelTests: XCTestCase {
    private var tree: TemporaryTree!
    private var home: FakeHome!
    private var model: SpaceLensViewModel!
    private let movieName = "movie.mov"

    override func setUpWithError() throws {
        tree = try TemporaryTree()
        home = try FakeHome(tree: tree)
        model = SpaceLensViewModel(builder: SizeTreeBuilder(minimumNodeBytes: 10_000),
                                   removal: try home.removalService(), home: home.home,
                                   protectedLocations: { _ in nil })
        try tree.makeFile("home/Downloads/\(movieName)", bytes: 300_000)
        try tree.makeFile("home/Downloads/setup.dmg", bytes: 100_000)
        try tree.makeFile("home/Documents/notes.txt", bytes: 50_000)
    }

    override func tearDown() {
        model = nil
        home = nil
        tree = nil
    }

    private func node(_ name: String, in folder: SizeNode?) throws -> SizeNode {
        try XCTUnwrap(folder?.children.first { $0.name == name })
    }

    func testSelectingAFolderReplacesItemsInsideIt() async throws {
        await model.scanHome()?.value
        let downloads = try node("Downloads", in: model.root)
        let movie = try node(movieName, in: downloads)

        model.toggle(movie)
        model.toggle(downloads)

        XCTAssertEqual(model.selection.map(\.name), ["Downloads"])
        model.toggle(movie)
        XCTAssertEqual(model.selection.map(\.name), [movieName])
    }

    func testTrashingPublishesItsProgressAndClearsItWhenDone() async throws {
        await model.scanHome()?.value
        let downloads = try node("Downloads", in: model.root)
        model.toggle(try node(movieName, in: downloads))
        model.toggle(try node("setup.dmg", in: downloads))
        let log = RemovalProgressLog(model.$removalProgress)

        await model.trashSelection()

        XCTAssertEqual(log.shown.first?.stage, .movingToTrash)
        XCTAssertEqual(log.shown.first?.total, 2)
        XCTAssertNil(model.removalProgress)
        XCTAssertTrue(log.endedEmpty)
        XCTAssertEqual(model.phase, .ready)
    }

    func testACancelledTrashingStillClearsItsProgress() async throws {
        await model.scanHome()?.value
        model.toggle(try node(movieName, in: try node("Downloads", in: model.root)))

        let trashing = Task { await model.trashSelection() }
        trashing.cancel()
        await trashing.value

        XCTAssertNil(model.removalProgress)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertTrue(tree.exists(home.url("Downloads/\(movieName)")))
    }

    func testStartingOverReturnsToTheStartScreen() async throws {
        await model.scanHome()?.value
        model.open(try node("Downloads", in: model.root))
        model.toggle(try node(movieName, in: model.current))

        model.startOver()

        XCTAssertEqual(model.phase, .idle)
        XCTAssertNil(model.root)
        XCTAssertTrue(model.path.isEmpty)
        XCTAssertTrue(model.selection.isEmpty)
        await model.scanHome()?.value
        XCTAssertEqual(model.phase, .ready)
    }

    func testTrashingMovesToTrashAndUpdatesTheTree() async throws {
        await model.scanHome()?.value
        let downloads = try node("Downloads", in: model.root)
        let movie = try node(movieName, in: downloads)
        let rootBefore = try XCTUnwrap(model.root).bytes
        model.toggle(movie)

        await model.trashSelection()

        XCTAssertFalse(tree.exists(home.url("Downloads/\(movieName)")))
        XCTAssertEqual(model.outcome?.removedCount, 1)
        XCTAssertNil(downloads.children.first { $0.name == movieName })
        XCTAssertEqual(model.root?.bytes, rootBefore - movie.bytes)
        XCTAssertTrue(model.selection.isEmpty)
    }

    func testCancelledScanKeepsTheMapOnScreen() async throws {
        await model.scanHome()?.value
        let before = try XCTUnwrap(model.root)

        let rescan = model.rescan()
        model.cancelScan()
        await rescan?.value

        XCTAssertTrue(model.root === before)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.path.map(\.name), [before.name])
    }

    func testCancelledFirstScanReturnsToTheStartScreen() async throws {
        let scan = model.scanHome()
        model.cancelScan()
        await scan?.value

        XCTAssertNil(model.root)
        XCTAssertEqual(model.phase, .idle)
    }

    func testLockedFolderCannotBeSelected() async throws {
        try tree.makeFile("home/Locked/inner.bin", bytes: 1_000)
        XCTAssertEqual(chmod(home.url("Locked").path, 0o000), 0)
        defer { chmod(home.url("Locked").path, 0o755) }
        await model.scanHome()?.value
        let locked = try node("Locked", in: model.root)

        model.toggle(locked)

        XCTAssertTrue(locked.isLocked)
        XCTAssertTrue(model.selection.isEmpty)
    }

    func testTrashingTheOpenFolderMovesToTheNearestSurvivor() async throws {
        try tree.makeFile("home/Documents/Projects/big.bin", bytes: 100_000)
        try tree.makeFile("home/Documents/Projects/sub/deep.bin", bytes: 100_000)
        await model.scanHome()?.value
        let documents = try node("Documents", in: model.root)
        let projects = try node("Projects", in: documents)
        let sub = try node("sub", in: projects)
        let deepPath = home.url("Documents/Projects/sub/deep.bin").path
        model.toggle(projects)
        model.open(documents)
        model.open(projects)
        model.open(sub)
        XCTAssertEqual(model.path.map(\.name), ["home", "Documents", "Projects", "sub"])

        await model.trashSelection()

        XCTAssertFalse(tree.exists(home.url("Documents/Projects")))
        XCTAssertEqual(model.path.map(\.name), ["home", "Documents"])
        XCTAssertTrue(model.current === documents)
        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertEqual(try node("deep.bin", in: sub).url.path, deepPath)
        XCTAssertEqual(documents.bytes, documents.children.reduce(documents.prunedBytes) { $0 + $1.bytes })
    }

    func testTrashingAnItemInsideTheOpenFolderKeepsTheView() async throws {
        await model.scanHome()?.value
        let downloads = try node("Downloads", in: model.root)
        model.open(downloads)
        model.toggle(try node(movieName, in: downloads))

        await model.trashSelection()

        XCTAssertTrue(model.current === downloads)
    }

    func testPurposeFollowsLocation() {
        XCTAssertEqual(model.purpose(for: home.url("Downloads/a.zip")), .userFile)
        XCTAssertEqual(model.purpose(for: home.url("Library/Application Support/App/data")), .appLeftover)
        XCTAssertEqual(model.purpose(for: URL(fileURLWithPath: "/Applications/Tool.app")), .appBundle)
        XCTAssertEqual(model.purpose(for: home.url("Library/Developer/Xcode/Archives/x.xcarchive")), .buildArchive)
    }

}
