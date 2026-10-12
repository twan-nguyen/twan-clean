import XCTest
@testable import TwanClean

final class PrivilegedRemoverTests: XCTestCase {
    private var tree: TemporaryTree!

    override func setUpWithError() throws {
        tree = try TemporaryTree()
    }

    override func tearDown() {
        tree = nil
    }

    private func identity(_ url: URL) throws -> FileIdentity {
        try XCTUnwrap(FileIdentity.of(url))
    }

    /// Runs the root command as the current user, which is enough to check
    /// its logic on files this user owns.
    private func runShell(_ command: String) async throws -> ProcessResult {
        let result = await ProcessRunner.run(URL(fileURLWithPath: "/bin/sh"), ["-c", command])
        return try XCTUnwrap(result)
    }

    // MARK: - Staging

    func testStagingWritesIdentityAndPathPairs() throws {
        let paths = ["/Library/Caches/a b", "/Library/Caches/it's \"quoted\"", "/Library/Caches/$(reboot)\nnext"]
        let staged = try PrivilegedRemover.stage(paths.enumerated().map {
            (FileIdentity(device: 7, inode: UInt64($0.offset)), $0.element)
        })
        defer { try? FileManager.default.removeItem(at: staged.file.deletingLastPathComponent()) }

        let fields = try Data(contentsOf: staged.file)
            .split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        XCTAssertEqual(fields, ["7:0", paths[0], "7:1", paths[1], "7:2", paths[2], ""])
        XCTAssertEqual(staged.digest.count, 64)

        let fileMode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: staged.file.path)[.posixPermissions] as? Int)
        XCTAssertEqual(fileMode & 0o777, 0o600)
    }

    func testStagingRejectsNUL() {
        XCTAssertThrowsError(try PrivilegedRemover.stage([(FileIdentity(device: 1, inode: 1), "/tmp/a\u{0}b")]))
    }

    // MARK: - Root command

    func testCommandRemovesItemsThatAreUnchanged() async throws {
        let file = try tree.makeFile("cache/blob")
        let folder = try tree.makeDirectory("cache/folder")
        try tree.makeFile("cache/folder/inner")
        let staged = try PrivilegedRemover.stage([(try identity(file), file.path), (try identity(folder), folder.path)])

        let result = try await runShell(try PrivilegedRemover.shellCommand(stagingFile: staged.file, digest: staged.digest))

        XCTAssertTrue(result.succeeded, result.errorText)
        XCTAssertFalse(tree.exists(file))
        XCTAssertFalse(tree.exists(folder))
    }

    func testCommandSkipsItemReplacedSinceValidation() async throws {
        let file = try tree.makeFile("cache/blob")
        let staged = try PrivilegedRemover.stage([(try identity(file), file.path)])
        try FileManager.default.removeItem(at: file)
        try tree.makeFile("cache/other")
        let replacement = try tree.makeFile("cache/blob")

        _ = try await runShell(try PrivilegedRemover.shellCommand(stagingFile: staged.file, digest: staged.digest))

        XCTAssertTrue(tree.exists(replacement))
    }

    func testCommandSkipsPathReachedThroughASwappedParent() async throws {
        let victim = try tree.makeFile("precious/data")
        let file = try tree.makeFile("cache/sub/data")
        let staged = try PrivilegedRemover.stage([(try identity(file), file.path)])
        try FileManager.default.removeItem(at: tree.url("cache/sub"))
        try tree.makeSymlink("cache/sub", to: tree.url("precious"))

        _ = try await runShell(try PrivilegedRemover.shellCommand(stagingFile: staged.file, digest: staged.digest))

        XCTAssertTrue(tree.exists(victim))
    }

    func testCommandRefusesATamperedList() async throws {
        let keep = try tree.makeFile("precious/data")
        let file = try tree.makeFile("cache/blob")
        let staged = try PrivilegedRemover.stage([(try identity(file), file.path)])
        let tampered = try PrivilegedRemover.stage([(try identity(keep), keep.path)])
        try FileManager.default.removeItem(at: staged.file)
        try FileManager.default.copyItem(at: tampered.file, to: staged.file)

        let result = try await runShell(try PrivilegedRemover.shellCommand(stagingFile: staged.file, digest: staged.digest))

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(tree.exists(keep))
        XCTAssertTrue(tree.exists(file))
    }

    func testItemScriptsNeverContainASingleQuote() throws {
        for action in [PrivilegedRemover.RootAction.remove, .stopSystemDaemon()] {
            XCTAssertFalse(try PrivilegedRemover.itemScript(action).contains("'"))
        }
        XCTAssertThrowsError(try PrivilegedRemover.itemScript(.stopSystemDaemon(daemonFolder: "/x'; reboot", launchctl: "/bin/launchctl")))
    }

    func testStopCommandStopsOnlyUnchangedPlistsDirectlyInTheDaemonFolder() async throws {
        let daemons = try tree.makeDirectory("LaunchDaemons")
        let log = tree.root.appendingPathComponent("launchctl.log")
        let launchctl = try tree.makeFile("bin/launchctl")
        try "#!/bin/sh\necho \"$@\" >> \(log.path)\n".write(to: launchctl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launchctl.path)
        let daemon = try tree.makeFile("LaunchDaemons/com.vendor.helper.plist")
        let nested = try tree.makeFile("LaunchDaemons/old/com.vendor.helper.plist")
        let replaced = try tree.makeFile("LaunchDaemons/com.vendor.replaced.plist")
        let notAPlist = try tree.makeFile("LaunchDaemons/readme.txt")
        let staged = try PrivilegedRemover.stage([
            (try identity(daemon), daemon.path), (try identity(nested), nested.path),
            (FileIdentity(device: 0, inode: 0), replaced.path), (try identity(notAPlist), notAPlist.path),
        ])
        let action = PrivilegedRemover.RootAction.stopSystemDaemon(daemonFolder: daemons.path, launchctl: launchctl.path)

        let result = try await runShell(try PrivilegedRemover.shellCommand(stagingFile: staged.file, digest: staged.digest,
                                                                           action: action))

        XCTAssertTrue(result.succeeded, result.errorText)
        XCTAssertEqual(try String(contentsOf: log, encoding: .utf8), "bootout system \(daemon.path)\n")
        for file in [daemon, nested, replaced, notAPlist] {
            XCTAssertTrue(tree.exists(file), "\(file.lastPathComponent) must be left for the Trash")
        }
    }

    func testRecognisesSystemDaemonPlists() {
        XCTAssertTrue(PrivilegedRemover.isSystemDaemon(URL(fileURLWithPath: "/Library/LaunchDaemons/com.vendor.helper.plist")))
        XCTAssertFalse(PrivilegedRemover.isSystemDaemon(URL(fileURLWithPath: "/Library/LaunchDaemons/old/com.vendor.helper.plist")))
        XCTAssertFalse(PrivilegedRemover.isSystemDaemon(URL(fileURLWithPath: "/Library/LaunchAgents/com.vendor.agent.plist")))
        XCTAssertFalse(PrivilegedRemover.isSystemDaemon(URL(fileURLWithPath: "/Library/LaunchDaemons/helper")))
    }

    func testCommandRejectsUnusualStagingPath() {
        let odd = URL(fileURLWithPath: "/tmp/it's here/paths")
        XCTAssertThrowsError(try PrivilegedRemover.shellCommand(stagingFile: odd, digest: String(repeating: "a", count: 64)))
    }

    // MARK: - AppleScript

    func testAppleScriptEscapesTheCommandAndPrompt() {
        let script = PrivilegedRemover.appleScript(shellCommand: #"echo "a" \ b"#, prompt: #"Say "hi""#)
        XCTAssertEqual(script, #"do shell script "echo \"a\" \\ b" with prompt "Say \"hi\"" with administrator privileges"#)
    }

    func testCancelledAuthorizationIsReported() async throws {
        let home = try FakeHome(tree: tree)
        let file = try tree.makeFile("home/Library/Caches/blob")
        let cancelled: PrivilegedRemover.ScriptRunner = { _ in
            ProcessResult(exitedNormally: true, status: 1, output: Data(),
                          errorOutput: Data("execution error: User canceled. (-128)".utf8), timedOut: false)
        }
        let remover = PrivilegedRemover(service: RemovalService(policy: home.policy), prompt: "x", runScript: cancelled)

        let report = await remover.remove([try home.request(file, .regenerableCache)])

        XCTAssertEqual(report.failed.count, 1)
        XCTAssertEqual(report.failed.first?.message, String(localized: "Administrator authorization was cancelled."))
        XCTAssertTrue(tree.exists(file))
    }

    func testOnlyItemsThatAreActuallyGoneCountAsRemoved() async throws {
        let home = try FakeHome(tree: tree)
        let gone = try tree.makeFile("home/Library/Caches/gone")
        let kept = try tree.makeFile("home/Library/Caches/kept")
        let requests = [try home.request(gone, .regenerableCache), try home.request(kept, .regenerableCache)]
        let partial: PrivilegedRemover.ScriptRunner = { _ in
            try? FileManager.default.removeItem(at: gone)
            return ProcessResult(exitedNormally: true, status: 0, output: Data(), errorOutput: Data(), timedOut: false)
        }
        let remover = PrivilegedRemover(service: RemovalService(policy: home.policy), prompt: "x", runScript: partial)

        let report = await remover.remove(requests)

        XCTAssertEqual(report.removed.map(\.url.lastPathComponent), ["gone"])
        XCTAssertEqual(report.failed.map(\.request.url.lastPathComponent), ["kept"])
    }

    func testCancelledAuthorizationIsRecognised() {
        XCTAssertTrue(AdministratorError(output: "execution error: User canceled. (-128)").wasCancelled)
        XCTAssertFalse(AdministratorError(output: "rm: Operation not permitted").wasCancelled)
    }
}
