import Foundation
import XCTest
@testable import TwanClean

/// A scratch folder for file system tests, removed when the test ends. Paths
/// are canonical so they match what `PathPolicy` reports.
final class TemporaryTree {
    let root: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("TwanCleanTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        root = URL(fileURLWithPath: SafetyRules.canonicalPath(base.path)!, isDirectory: true)
    }

    deinit {
        // Restore permissions first so locked folders can be removed.
        if let enumerator = FileManager.default.enumerator(atPath: root.path) {
            for case let relative as String in enumerator {
                chmod(root.appendingPathComponent(relative).path, 0o755)
            }
        }
        try? FileManager.default.removeItem(at: root)
    }

    func url(_ relative: String) -> URL {
        root.appendingPathComponent(relative)
    }

    @discardableResult
    func makeDirectory(_ relative: String) throws -> URL {
        let url = url(relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func makeFile(_ relative: String, bytes: Int = 16) throws -> URL {
        let url = url(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 0x61, count: bytes)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    @discardableResult
    func makeSymlink(_ relative: String, to destination: URL) throws -> URL {
        let url = url(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: destination)
        return url
    }

    func exists(_ url: URL) -> Bool {
        FileIdentity.of(url) != nil
    }
}

/// A fake home folder inside a `TemporaryTree`, with rules bound to it.
struct FakeHome {
    let tree: TemporaryTree
    let home: URL
    let rules: SafetyRules
    let policy: PathPolicy

    init(tree: TemporaryTree) throws {
        self.tree = tree
        home = try tree.makeDirectory("home")
        for folder in ["Library/Caches", "Library/Preferences", "Documents", "Downloads", "Desktop", ".Trash"] {
            try tree.makeDirectory("home/\(folder)")
        }
        rules = SafetyRules(homeDirectory: home)
        policy = PathPolicy(rules: rules)
    }

    func url(_ relative: String) -> URL {
        home.appendingPathComponent(relative)
    }

    /// A removal service whose Trash is a folder in this tree, so tests never
    /// touch the user's real Trash.
    func removalService() throws -> RemovalService {
        let trashFolder = try tree.makeDirectory("trash")
        return RemovalService(policy: policy) { url in
            let destination = trashFolder.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    func request(_ url: URL, _ purpose: RemovalPurpose, bytes: Int64 = 0) throws -> RemovalRequest {
        let identity = try XCTUnwrap(FileIdentity.of(url), "missing \(url.path)")
        return RemovalRequest(url: url, purpose: purpose, identity: identity, bytes: bytes)
    }
}
