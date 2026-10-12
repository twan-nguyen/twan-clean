import XCTest
@testable import TwanClean

@MainActor
final class SmartScanViewModelTests: XCTestCase {
    private var tree: TemporaryTree!
    private var home: FakeHome!

    override func setUpWithError() throws {
        tree = try TemporaryTree()
        home = try FakeHome(tree: tree)
        try tree.makeFile("home/Library/Caches/com.example.editor/cache.db", bytes: 8_192)
        try tree.makeFile("home/Library/Caches/com.example.player/blob", bytes: 8_192)
        try tree.makeFile("home/Downloads/huge.iso", bytes: 300_000)
    }

    override func tearDown() {
        home = nil
        tree = nil
    }

    private func makeModel() -> SmartScanViewModel {
        var settings = ScanSettings()
        settings.largeFileMinimumBytes = 200_000
        let home = home!
        return SmartScanViewModel(
            coordinator: SmartScanCoordinator(scanners: [UserCacheScanner(), LargeOldFilesScanner()]),
            removal: RemovalService(policy: home.policy),
            makeContext: { _ in home.scanContext(settings: settings) })
    }

    func testScanSelectsOnlyDefaultSelectedItems() async {
        let model = makeModel()
        await model.startScan([.userCache, .largeOld])?.value

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(Set(model.selectedItems().map(\.name)), ["com.example.editor", "com.example.player"])
        XCTAssertEqual(model.items(in: .largeOld).map(\.name), ["huge.iso"])
    }

    func testCleaningRemovesSelectedItemsAndReportsFreedSpace() async {
        let model = makeModel()
        await model.startScan([.userCache, .largeOld])?.value
        let player = model.items(in: .userCache).first { $0.name == "com.example.player" }!
        model.setSelected(player, false)
        let expected = model.selectedBytes()

        await model.clean()

        XCTAssertEqual(model.outcome?.freedBytes, expected)
        XCTAssertEqual(model.items(in: .userCache).map(\.name), ["com.example.player"])
        XCTAssertFalse(tree.exists(home.url("Library/Caches/com.example.editor")))
        XCTAssertTrue(tree.exists(home.url("Library/Caches/com.example.player")))
        XCTAssertTrue(tree.exists(home.url("Downloads/huge.iso")))
    }

    func testRescanningOneCategoryKeepsTheOthers() async {
        let model = makeModel()
        await model.startScan([.userCache, .largeOld])?.value
        await model.startScan([.largeOld])?.value

        XCTAssertFalse(model.items(in: .userCache).isEmpty)
        XCTAssertEqual(model.selectedItems(in: [.userCache]).count, 2)
    }
}
