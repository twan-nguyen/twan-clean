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

    func testPurposeFollowsLocation() {
        XCTAssertEqual(model.purpose(for: home.url("Downloads/a.zip")), .userFile)
        XCTAssertEqual(model.purpose(for: home.url("Library/Application Support/App/data")), .appLeftover)
        XCTAssertEqual(model.purpose(for: URL(fileURLWithPath: "/Applications/Tool.app")), .appBundle)
        XCTAssertEqual(model.purpose(for: home.url("Library/Developer/Xcode/Archives/x.xcarchive")), .buildArchive)
    }

}
