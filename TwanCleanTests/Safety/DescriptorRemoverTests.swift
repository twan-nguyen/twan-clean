import XCTest
@testable import TwanClean

final class DescriptorRemoverTests: XCTestCase {
    private var tree: TemporaryTree!

    override func setUpWithError() throws {
        tree = try TemporaryTree()
    }

    override func tearDown() {
        tree = nil
    }

    private func remove(_ url: URL, afterListing: @escaping (String) -> Void = { _ in }) throws {
        try DescriptorRemover.remove(url, expecting: try XCTUnwrap(FileIdentity.of(url)), afterListing: afterListing)
    }

    func testRemovesANestedTreeWithHiddenFilesAndSpecialFiles() throws {
        try tree.makeFile("item/a.bin", bytes: 4096)
        try tree.makeFile("item/.hidden")
        try tree.makeFile("item/deep/er/est/file")
        try tree.makeDirectory("item/empty")
        XCTAssertEqual(mkfifo(tree.url("item/deep/pipe").path, 0o600), 0)

        try remove(tree.url("item"))

        XCTAssertFalse(tree.exists(tree.url("item")))
        XCTAssertTrue(tree.exists(tree.root))
    }

    func testRemovesAFile() throws {
        let file = try tree.makeFile("parent/file")
        try remove(file)
        XCTAssertFalse(tree.exists(file))
        XCTAssertTrue(tree.exists(tree.url("parent")))
    }

    func testSymlinkIsRemovedAndItsTargetKept() throws {
        let target = try tree.makeFile("outside/keep.txt")
        let link = try tree.makeSymlink("parent/link", to: tree.url("outside"))

        try remove(link)

        XCTAssertFalse(tree.exists(link))
        XCTAssertTrue(tree.exists(target))
    }

    func testSymlinkedFoldersInsideTheTreeAreNeverFollowed() throws {
        let keep = try tree.makeFile("outside/keep.txt")
        try tree.makeSymlink("item/sub/link", to: tree.url("outside"))
        try tree.makeSymlink("item/dangling", to: tree.url("nowhere"))

        try remove(tree.url("item"))

        XCTAssertFalse(tree.exists(tree.url("item")))
        XCTAssertTrue(tree.exists(keep))
    }

    func testFolderSwappedForASymlinkAfterTheListingIsNotFollowed() throws {
        let keep = try tree.makeFile("outside/dir/keep.txt")
        try tree.makeFile("item/sub/inner.txt")
        try tree.makeFile("item/sub/more/file")
        let outside = tree.url("outside/dir")

        try remove(tree.url("item")) { path in
            guard path == self.tree.url("item").path else { return }
            // The listing has seen "sub" as a real folder; now it is a link.
            try? FileManager.default.removeItem(at: self.tree.url("item/sub"))
            try? FileManager.default.createSymbolicLink(at: self.tree.url("item/sub"), withDestinationURL: outside)
        }

        XCTAssertFalse(tree.exists(tree.url("item")))
        XCTAssertTrue(tree.exists(keep))
    }

    func testDeeperFolderSwappedForASymlinkIsNotFollowed() throws {
        let keep = try tree.makeFile("outside/dir/keep.txt")
        try tree.makeFile("item/a/b/file")
        let outside = tree.url("outside/dir")

        try remove(tree.url("item")) { path in
            guard path == self.tree.url("item/a").path else { return }
            try? FileManager.default.removeItem(at: self.tree.url("item/a/b"))
            try? FileManager.default.createSymbolicLink(at: self.tree.url("item/a/b"), withDestinationURL: outside)
        }

        XCTAssertFalse(tree.exists(tree.url("item")))
        XCTAssertTrue(tree.exists(keep))
    }

    func testFileSwappedForAFolderIsNotEmptiedThroughTheLink() throws {
        // A name listed as a file that becomes a link to a folder is unlinked
        // as the link it is; the folder behind it is untouched.
        let keep = try tree.makeFile("outside/dir/keep.txt")
        try tree.makeFile("item/target.bin")
        let outside = tree.url("outside/dir")

        try remove(tree.url("item")) { path in
            guard path == self.tree.url("item").path else { return }
            try? FileManager.default.removeItem(at: self.tree.url("item/target.bin"))
            try? FileManager.default.createSymbolicLink(at: self.tree.url("item/target.bin"), withDestinationURL: outside)
        }

        XCTAssertFalse(tree.exists(tree.url("item")))
        XCTAssertTrue(tree.exists(keep))
    }

    func testRefusesAnItemThatIsNotTheScannedObject() throws {
        let item = try tree.makeFile("parent/item")
        let scanned = try XCTUnwrap(FileIdentity.of(item))
        try FileManager.default.removeItem(at: item)
        try tree.makeFile("parent/padding")
        try tree.makeFile("parent/item")

        XCTAssertThrowsError(try DescriptorRemover.remove(item, expecting: scanned)) { error in
            XCTAssertEqual(error as? DescriptorRemover.Failure, .changed(item.path))
        }
        XCTAssertTrue(tree.exists(item))
    }

    func testUnreadableFolderFailsWithAPermissionError() throws {
        try tree.makeFile("item/locked/inner")
        let locked = tree.url("item/locked")
        XCTAssertEqual(chmod(locked.path, 0o000), 0)
        defer { chmod(locked.path, 0o755) }
        let keep = try tree.makeFile("item/removable")

        XCTAssertThrowsError(try remove(tree.url("item"))) { error in
            XCTAssertTrue(RemovalService.isPermissionError(error), "\(error)")
        }
        XCTAssertFalse(tree.exists(keep))
        XCTAssertTrue(tree.exists(locked))
    }

    func testMountedVolumeInsideTheTreeIsLeftAloneAndReported() throws {
        let item = try tree.makeDirectory("item")
        try tree.makeFile("item/before.bin")
        try tree.makeFile("item/zones/zone.bin")
        let image = try MountedImage(at: tree.url("item/zones/volume"), imageFolder: tree.root)
        defer { image.detach() }
        let precious = try tree.makeFile("item/zones/volume/precious.txt")

        XCTAssertThrowsError(try remove(item)) { error in
            XCTAssertEqual(error as? DescriptorRemover.Failure, .mountPoint(tree.url("item/zones/volume").path))
        }

        XCTAssertTrue(tree.exists(precious))
        XCTAssertFalse(tree.exists(tree.url("item/before.bin")))
        XCTAssertFalse(tree.exists(tree.url("item/zones/zone.bin")))
    }
}
