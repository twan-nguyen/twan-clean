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
        // The timeout keeps a command that wrongly blocks from hanging the suite.
        let result = await ProcessRunner.run(URL(fileURLWithPath: "/bin/sh"), ["-c", command], timeout: 30)
        return try XCTUnwrap(result)
    }

    // MARK: - Staging

    func testStagingWritesItemAndParentIdentitiesWithTheParentPathAndName() throws {
        let names = ["a b", "it's \"quoted\"", "$(reboot)\nnext"]
        let urls = try names.map { try tree.makeFile("cache/\($0)") }
        let staged = try PrivilegedRemover.stage(urls.enumerated().map {
            (FileIdentity(device: 7, inode: UInt64($0.offset)), $0.element.path)
        })
        defer { try? FileManager.default.removeItem(at: staged.file.deletingLastPathComponent()) }

        let parent = tree.url("cache")
        let parentToken = PrivilegedRemover.identityToken(try identity(parent))
        let fields = try Data(contentsOf: staged.file)
            .split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        XCTAssertEqual(fields, names.enumerated().flatMap { ["7:\($0.offset)", parentToken, parent.path, $0.element] } + [""])
        XCTAssertEqual(staged.digest.count, 64)

        let fileMode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: staged.file.path)[.posixPermissions] as? Int)
        XCTAssertEqual(fileMode & 0o777, 0o600)
    }

    func testStagingRejectsNUL() {
        XCTAssertThrowsError(try PrivilegedRemover.stage([(FileIdentity(device: 1, inode: 1), "/tmp/a\u{0}b")]))
    }

    func testStagingRejectsAnItemWhoseFolderCannotBeExamined() {
        XCTAssertThrowsError(try PrivilegedRemover.stage([(FileIdentity(device: 1, inode: 1),
                                                           tree.url("missing/folder/item").path)]))
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

    func testCommandSkipsPathWhoseAncestorWasSwappedForALink() async throws {
        let file = try tree.makeFile("cache/sub/data")
        // A hard link gives the other tree an item with the staged identity,
        // so only the folder check can tell the two paths apart.
        try tree.makeDirectory("precious/sub")
        let victim = tree.url("precious/sub/data")
        try FileManager.default.linkItem(at: file, to: victim)
        let staged = try PrivilegedRemover.stage([(try identity(file), file.path)])
        try FileManager.default.moveItem(at: tree.url("cache"), to: tree.url("cache-moved"))
        try tree.makeSymlink("cache", to: tree.url("precious"))

        _ = try await runShell(try PrivilegedRemover.shellCommand(stagingFile: staged.file, digest: staged.digest))

        XCTAssertTrue(tree.exists(victim))
        XCTAssertTrue(tree.exists(tree.url("cache-moved/sub/data")))
    }

    func testCommandRemovesTheItemRelativeToItsFolderWhateverTheNameLooksLike() async throws {
        let odd = try tree.makeFile("cache/-rf name\nwith $(touch pwned) 'quotes'")
        let sibling = try tree.makeFile("cache/sibling")
        let staged = try PrivilegedRemover.stage([(try identity(odd), odd.path)])

        let result = try await runShell(try PrivilegedRemover.shellCommand(stagingFile: staged.file, digest: staged.digest))

        XCTAssertTrue(result.succeeded, result.errorText)
        XCTAssertFalse(tree.exists(odd))
        XCTAssertTrue(tree.exists(sibling))
        XCTAssertFalse(tree.exists(tree.url("cache/pwned")))
    }

    func testCommandRefusesAListThatIsNotAPlainFile() async throws {
        let keep = try tree.makeFile("cache/keep")
        let staged = try PrivilegedRemover.stage([(try identity(keep), keep.path)])
        try FileManager.default.removeItem(at: staged.file)

        // A FIFO would block `cat` forever.
        XCTAssertEqual(mkfifo(staged.file.path, 0o600), 0)
        var result = try await runShell(try PrivilegedRemover.shellCommand(stagingFile: staged.file, digest: staged.digest))
        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(result.timedOut)

        // A link to a list with the right content is not accepted either.
        let real = try PrivilegedRemover.stage([(try identity(keep), keep.path)])
        try FileManager.default.removeItem(at: staged.file)
        try FileManager.default.createSymbolicLink(at: staged.file, withDestinationURL: real.file)
        result = try await runShell(try PrivilegedRemover.shellCommand(stagingFile: staged.file, digest: real.digest))
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(tree.exists(keep))
    }

    func testCommandNeedsNoScriptInterpreterForTheDigestAndStartsWithAnEmptyEnvironment() throws {
        let staged = try PrivilegedRemover.stage([(try identity(tree.root), tree.root.appendingPathComponent("x").path)])
        defer { try? FileManager.default.removeItem(at: staged.file.deletingLastPathComponent()) }

        let command = try PrivilegedRemover.shellCommand(stagingFile: staged.file, digest: staged.digest)

        XCTAssertTrue(command.hasPrefix("/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/sh -c '"))
        XCTAssertFalse(command.contains("shasum"))
        XCTAssertFalse(command.contains("perl"))
        XCTAssertTrue(command.contains("/usr/bin/openssl dgst -sha256"))
    }

    func testCommandRunsItsToolsWithoutTheCallersEnvironment() async throws {
        let daemons = try tree.makeDirectory("LaunchDaemons")
        let seen = tree.root.appendingPathComponent("environment.log")
        let launchctl = try tree.makeFile("bin/launchctl")
        try "#!/bin/sh\n/usr/bin/env > \(seen.path)\n".write(to: launchctl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launchctl.path)
        let daemon = try tree.makeFile("LaunchDaemons/com.vendor.helper.plist")
        let staged = try PrivilegedRemover.stage([(try identity(daemon), daemon.path)])
        let action = PrivilegedRemover.RootAction.stopSystemDaemon(daemonFolder: daemons.path, launchctl: launchctl.path)
        setenv("TWAN_TEST_PROBE", "leaked", 1)
        setenv("PERL5OPT", "-Mleaked", 1)
        defer {
            unsetenv("TWAN_TEST_PROBE")
            unsetenv("PERL5OPT")
        }

        let result = try await runShell(try PrivilegedRemover.shellCommand(stagingFile: staged.file, digest: staged.digest,
                                                                           action: action))

        XCTAssertTrue(result.succeeded, result.errorText)
        let environment = try String(contentsOf: seen, encoding: .utf8)
        XCTAssertFalse(environment.contains("TWAN_TEST_PROBE"))
        XCTAssertFalse(environment.contains("PERL5OPT"))
        XCTAssertTrue(environment.contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin"))
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

    func testRootCommandSurvivesAppleScriptQuotingIntact() throws {
        let staged = try PrivilegedRemover.stage([(try identity(tree.root), tree.url("x").path)])
        defer { try? FileManager.default.removeItem(at: staged.file.deletingLastPathComponent()) }
        let command = try PrivilegedRemover.shellCommand(stagingFile: staged.file, digest: staged.digest)

        let literal = PrivilegedRemover.appleScriptLiteral(command)

        // Reading the literal back the way AppleScript does gives the command.
        var decoded = ""
        var escaped = false
        for character in literal.dropFirst().dropLast() {
            if escaped || character != "\\" { decoded.append(character); escaped = false } else { escaped = true }
        }
        XCTAssertEqual(decoded, command)
        XCTAssertTrue(command.contains(#"'\''"#), "the per-item script is quoted inside the outer quotes")
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

    // MARK: - Trash

    /// Collects what the injected runner and recycler were asked to do, in order.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []
        var events: [String] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        func record(_ event: String) {
            lock.lock()
            storage.append(event)
            lock.unlock()
        }
    }

    private let succeeded = ProcessResult(exitedNormally: true, status: 0, output: Data(), errorOutput: Data(), timedOut: false)

    /// A remover whose script runner and Trash are fakes, so nothing real
    /// runs and the Trash is a folder in the test tree.
    private func fakeRemover(_ home: FakeHome, recorder: Recorder, daemonFolder: URL,
                             beforeRecycle: @escaping @Sendable ([URL]) -> Void = { _ in }) throws -> PrivilegedRemover {
        let trash = try tree.makeDirectory("fake-trash")
        let result = succeeded
        return PrivilegedRemover(
            service: RemovalService(policy: home.policy), prompt: "x",
            runScript: { script in
                recorder.record("script: \(script)")
                return result
            },
            recycle: { urls in
                recorder.record("recycle: \(urls.map(\.lastPathComponent).joined(separator: ","))")
                beforeRecycle(urls)
                var moved: [URL: URL] = [:]
                for url in urls where FileIdentity.of(url) != nil {
                    let destination = trash.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.moveItem(at: url, to: destination)
                    moved[url] = destination
                }
                return moved
            },
            daemonFolder: daemonFolder.path)
    }

    func testDaemonPlistsAreStoppedBeforeTheyAreRecycled() async throws {
        let home = try FakeHome(tree: tree)
        let daemons = try tree.makeDirectory("home/Library/LaunchDaemons")
        let plist = try tree.makeFile("home/Library/LaunchDaemons/com.vendor.helper.plist")
        let support = try tree.makeFile("home/Library/Application Support/com.vendor/data")
        let recorder = Recorder()
        let remover = try fakeRemover(home, recorder: recorder, daemonFolder: daemons)

        let report = await remover.remove([try home.request(plist, .appLeftover), try home.request(support, .appLeftover)])

        let events = recorder.events
        XCTAssertEqual(events.count, 2, "\(events)")
        XCTAssertTrue(events[0].hasPrefix("script: do shell script"), events[0])
        XCTAssertTrue(events[0].contains("bootout system"), events[0])
        XCTAssertTrue(events[0].contains(daemons.path), events[0])
        XCTAssertEqual(events[1], "recycle: com.vendor.helper.plist,data")
        XCTAssertEqual(report.removed.count, 2)
        XCTAssertTrue(report.failed.isEmpty)
        XCTAssertFalse(tree.exists(plist))
    }

    func testNoDaemonStepRunsWithoutADaemonPlist() async throws {
        let home = try FakeHome(tree: tree)
        let daemons = try tree.makeDirectory("home/Library/LaunchDaemons")
        let agent = try tree.makeFile("home/Library/LaunchAgents/com.vendor.agent.plist")
        let nested = try tree.makeFile("home/Library/LaunchDaemons/old/com.vendor.helper.plist")
        let recorder = Recorder()
        let remover = try fakeRemover(home, recorder: recorder, daemonFolder: daemons)

        _ = await remover.remove([try home.request(agent, .appLeftover), try home.request(nested, .appLeftover)])

        XCTAssertEqual(recorder.events, ["recycle: com.vendor.agent.plist,com.vendor.helper.plist"])
    }

    func testItemReplacedBeforeTheTrashIsLeftAlone() async throws {
        let home = try FakeHome(tree: tree)
        let daemons = try tree.makeDirectory("home/Library/LaunchDaemons")
        let app = try tree.makeDirectory("home/Library/Application Support/com.vendor")
        let request = try home.request(app, .appLeftover)
        try FileManager.default.removeItem(at: app)
        try tree.makeFile("home/Library/Application Support/padding")
        try tree.makeDirectory("home/Library/Application Support/com.vendor")
        let recorder = Recorder()
        let remover = try fakeRemover(home, recorder: recorder, daemonFolder: daemons)

        let report = await remover.remove([request])

        XCTAssertEqual(report.refused.map(\.reason), [.changedSinceScan])
        XCTAssertTrue(report.removed.isEmpty)
        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertTrue(tree.exists(app))
    }

    func testItemSwappedWhileTheTrashPromptWasOpenIsNotCountedAsRemoved() async throws {
        let home = try FakeHome(tree: tree)
        let daemons = try tree.makeDirectory("home/Library/LaunchDaemons")
        let app = try tree.makeDirectory("home/Library/Application Support/com.vendor")
        let request = try home.request(app, .appLeftover)
        // An updater replaces the folder while the prompt is open, and the
        // Trash never reports moving the scanned one.
        let swap: PrivilegedRemover.Recycler = { urls in
            let url = urls[0]
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent().appendingPathComponent("padding"),
                                                    withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            return [:]
        }
        let remover = PrivilegedRemover(service: RemovalService(policy: home.policy), prompt: "x", runScript: { _ in nil },
                                        recycle: swap, daemonFolder: daemons.path)

        let report = await remover.remove([request])

        XCTAssertTrue(report.removed.isEmpty)
        XCTAssertEqual(report.failed.count, 1)
        XCTAssertTrue(tree.exists(app))
    }

    func testCancelledAuthorizationIsRecognised() {
        XCTAssertTrue(AdministratorError(output: "execution error: User canceled. (-128)").wasCancelled)
        XCTAssertFalse(AdministratorError(output: "rm: Operation not permitted").wasCancelled)
    }
}
