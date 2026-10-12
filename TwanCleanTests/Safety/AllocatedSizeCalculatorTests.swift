import XCTest
@testable import TwanClean

final class AllocatedSizeCalculatorTests: XCTestCase {
    private var tree: TemporaryTree!

    override func setUpWithError() throws {
        tree = try TemporaryTree()
    }

    override func tearDown() {
        tree = nil
    }

    private func blocks(_ url: URL) -> Int64 {
        var status = stat()
        lstat(url.path, &status)
        return Int64(status.st_blocks) * 512
    }

    func testCountsAllocatedBlocksIncludingHiddenFiles() throws {
        let visible = try tree.makeFile("data/visible.bin", bytes: 10_000)
        let hidden = try tree.makeFile("data/.hidden.bin", bytes: 5_000)

        let size = try AllocatedSizeCalculator().measure(tree.url("data"))

        XCTAssertEqual(size.bytes, blocks(visible) + blocks(hidden))
        XCTAssertGreaterThanOrEqual(size.bytes, 15_000)
        XCTAssertEqual(size.fileCount, 2)
    }

    func testHardLinkedFileIsCountedOnce() throws {
        let original = try tree.makeFile("data/original.bin", bytes: 20_000)
        try FileManager.default.linkItem(at: original, to: tree.url("data/link.bin"))

        let size = try AllocatedSizeCalculator().measure(tree.url("data"))

        XCTAssertEqual(size.bytes, blocks(original))
    }

    func testSessionDeduplicatesHardLinksAcrossMeasurements() throws {
        let original = try tree.makeFile("a/original.bin", bytes: 20_000)
        try tree.makeDirectory("b")
        try FileManager.default.linkItem(at: original, to: tree.url("b/link.bin"))
        let calculator = AllocatedSizeCalculator(session: SizingSession())

        let first = try calculator.measure(tree.url("a"))
        let second = try calculator.measure(tree.url("b"))

        XCTAssertEqual(first.bytes + second.bytes, blocks(original))
    }

    func testSymlinkTargetIsNotCounted() throws {
        let big = try tree.makeFile("outside/big.bin", bytes: 1_000_000)
        try tree.makeSymlink("data/link", to: big)

        let size = try AllocatedSizeCalculator().measure(tree.url("data"))

        XCTAssertLessThan(size.bytes, 100_000)
    }

    func testLargeFolderIsMeasuredWithoutACap() throws {
        let folder = try tree.makeDirectory("many")
        for index in 0..<12_000 {
            FileManager.default.createFile(atPath: folder.appendingPathComponent("f\(index)").path, contents: Data([1]))
        }

        let size = try AllocatedSizeCalculator().measure(folder)

        XCTAssertEqual(size.fileCount, 12_000)
    }

    func testUnreadableFolderIsReported() throws {
        try tree.makeFile("data/locked/inside.bin")
        let locked = tree.url("data/locked")
        XCTAssertEqual(chmod(locked.path, 0o000), 0)
        defer { chmod(locked.path, 0o755) }

        let size = try AllocatedSizeCalculator().measure(tree.url("data"))

        XCTAssertEqual(size.unreadableDirectories, 1)
        XCTAssertEqual(size.fileCount, 0)
    }

    func testCancellationStopsTheWalk() async throws {
        let folder = try tree.makeDirectory("many")
        for index in 0..<2_000 {
            FileManager.default.createFile(atPath: folder.appendingPathComponent("f\(index)").path, contents: Data([1]))
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try AllocatedSizeCalculator().measure(folder)
        }
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
        }
    }
}
