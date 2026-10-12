import XCTest
@testable import TwanClean

final class FileTreeWalkerTests: XCTestCase {
    private var tree: TemporaryTree!

    override func setUpWithError() throws {
        tree = try TemporaryTree()
    }

    override func tearDown() {
        tree = nil
    }

    private func events(_ root: URL, skipping skippedName: String? = nil) throws -> [String] {
        var events: [String] = []
        try FileTreeWalker.walk(root) { entry in
            let label: String
            switch entry.kind {
            case .directory: label = "open \(entry.name)"
            case .directoryEnd: label = "close \(entry.name)"
            case .file: label = "file \(entry.name)"
            case .symlink: label = "link \(entry.name)"
            case .unreadableDirectory: label = "denied \(entry.name)"
            case .unreadable: label = "unreadable \(entry.name)"
            }
            events.append(label)
            return entry.kind == .directory && entry.name == skippedName ? .skipDescendants : .continue
        }
        return events
    }

    func testOpensAndClosesFoldersAroundTheirContents() throws {
        try tree.makeFile("root/a/x")
        XCTAssertEqual(try events(tree.url("root")), ["open root", "open a", "file x", "close a", "close root"])
    }

    func testSkippedFolderIsNotClosed() throws {
        try tree.makeFile("root/sub/Tool.app/Contents/binary")
        try tree.makeFile("root/sub/after")

        let events = try events(tree.url("root"), skipping: "Tool.app")

        XCTAssertEqual(events.filter { $0.hasPrefix("open") }.count, events.filter { $0.hasPrefix("close") || $0.hasPrefix("denied") }.count + 1)
        XCTAssertFalse(events.contains("close Tool.app"))
        XCTAssertFalse(events.contains("file binary"))
        XCTAssertEqual(events.last, "close root")
    }

    func testUnreadableFolderReplacesItsClose() throws {
        try tree.makeFile("root/locked/x")
        chmod(tree.url("root/locked").path, 0o000)
        defer { chmod(tree.url("root/locked").path, 0o755) }

        XCTAssertEqual(try events(tree.url("root")), ["open root", "open locked", "denied locked", "close root"])
    }

    func testMissingRootIsReportedAsUnreadable() throws {
        XCTAssertEqual(try events(tree.url("missing")), ["unreadable missing"])
    }
}
