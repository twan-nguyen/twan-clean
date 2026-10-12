import XCTest
@testable import TwanClean

final class SizeTreeBuilderTests: XCTestCase {
    private var tree: TemporaryTree!
    private let builder = SizeTreeBuilder(minimumNodeBytes: 50_000)

    override func setUpWithError() throws {
        tree = try TemporaryTree()
    }

    override func tearDown() {
        tree = nil
    }

    private func blocks(_ relative: String) -> Int64 {
        var status = stat()
        lstat(tree.url(relative).path, &status)
        return Int64(status.st_blocks) * 512
    }

    private func child(_ node: SizeNode, _ name: String) -> SizeNode? {
        node.children.first { $0.name == name }
    }

    func testTotalsMatchTheFilesOnDisk() async throws {
        try tree.makeFile("root/a/big.bin", bytes: 200_000)
        try tree.makeFile("root/b/medium.bin", bytes: 100_000)
        try tree.makeFile("root/top.bin", bytes: 80_000)

        let root = try await builder.build(tree.url("root"))

        XCTAssertEqual(root.bytes, blocks("root/a/big.bin") + blocks("root/b/medium.bin") + blocks("root/top.bin"))
        XCTAssertEqual(root.children.map(\.name), ["a", "b", "top.bin"])
        XCTAssertEqual(child(root, "a")?.children.first?.name, "big.bin")
    }

    func testSmallItemsAreFoldedIntoTheirFolder() async throws {
        try tree.makeFile("root/a/big.bin", bytes: 200_000)
        try tree.makeFile("root/a/small1", bytes: 1_000)
        try tree.makeFile("root/a/small2", bytes: 1_000)
        try tree.makeFile("root/tiny/x", bytes: 1_000)

        let root = try await builder.build(tree.url("root"))
        let folder = try XCTUnwrap(child(root, "a"))

        XCTAssertEqual(folder.children.map(\.name), ["big.bin"])
        XCTAssertEqual(folder.prunedCount, 2)
        XCTAssertEqual(folder.bytes, blocks("root/a/big.bin") + blocks("root/a/small1") + blocks("root/a/small2"))
        XCTAssertNil(child(root, "tiny"))
        XCTAssertEqual(root.prunedCount, 1)
    }

    func testBundleIsOneItem() async throws {
        try tree.makeFile("root/Tool.app/Contents/MacOS/tool", bytes: 120_000)

        let root = try await builder.build(tree.url("root"))
        let app = try XCTUnwrap(child(root, "Tool.app"))

        XCTAssertEqual(app.kind, .package)
        XCTAssertTrue(app.children.isEmpty)
        XCTAssertEqual(app.bytes, blocks("root/Tool.app/Contents/MacOS/tool"))
    }

    func testBundleInsideAFolderIsOneItem() async throws {
        try tree.makeFile("root/Apps/Tool.app/Contents/MacOS/tool", bytes: 120_000)
        try tree.makeFile("root/Apps/after.bin", bytes: 60_000)

        let root = try await builder.build(tree.url("root"))
        let apps = try XCTUnwrap(child(root, "Apps"))

        XCTAssertEqual(Set(apps.children.map(\.name)), ["Tool.app", "after.bin"])
        XCTAssertEqual(child(apps, "Tool.app")?.kind, .package)
    }

    func testSymlinksAreNotFollowed() async throws {
        try tree.makeFile("outside/huge.bin", bytes: 500_000)
        try tree.makeFile("root/a/file.bin", bytes: 60_000)
        try tree.makeSymlink("root/a/link", to: tree.url("outside"))

        let root = try await builder.build(tree.url("root"))

        XCTAssertLessThan(root.bytes, 200_000)
    }

    func testHardLinksAreCountedOnce() async throws {
        let original = try tree.makeFile("root/a/original.bin", bytes: 200_000)
        try tree.makeDirectory("root/b")
        try FileManager.default.linkItem(at: original, to: tree.url("root/b/link.bin"))

        let root = try await builder.build(tree.url("root"))

        XCTAssertEqual(root.bytes, blocks("root/a/original.bin"))
    }

    func testUnreadableFolderIsMarked() async throws {
        try tree.makeFile("root/locked/inner.bin", bytes: 1_000)
        try tree.makeFile("root/open/file.bin", bytes: 60_000)
        XCTAssertEqual(chmod(tree.url("root/locked").path, 0o000), 0)
        defer { chmod(tree.url("root/locked").path, 0o755) }

        let root = try await builder.build(tree.url("root"))

        XCTAssertEqual(child(root, "locked")?.isAccessDenied, true)
    }

    func testRemovingANodeUpdatesEveryAncestor() async throws {
        try tree.makeFile("root/a/b/big.bin", bytes: 200_000)
        try tree.makeFile("root/a/other.bin", bytes: 100_000)
        let root = try await builder.build(tree.url("root"))
        let a = try XCTUnwrap(child(root, "a"))
        let b = try XCTUnwrap(child(a, "b"))
        let before = root.bytes

        a.remove(b)

        XCTAssertEqual(root.bytes, before - b.bytes)
        XCTAssertEqual(a.bytes, blocks("root/a/other.bin"))
        XCTAssertNil(child(a, "b"))
    }

    func testNodeURLsRebuildFullPaths() async throws {
        try tree.makeFile("root/a/b/big.bin", bytes: 200_000)
        let root = try await builder.build(tree.url("root"))
        let file = try XCTUnwrap(child(root, "a").flatMap { child($0, "b") }.flatMap { child($0, "big.bin") })
        XCTAssertEqual(file.url.path, tree.url("root/a/b/big.bin").path)
    }
}
