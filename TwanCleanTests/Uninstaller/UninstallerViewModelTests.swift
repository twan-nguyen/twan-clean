import XCTest
@testable import TwanClean

/// Processes that exist only in the test: nothing here signals, quits or
/// unloads anything real.
@MainActor
final class FakeProcessControl: AppProcessControl {
    /// What is running at each look; called once per look.
    var next: () -> [RunningProcess] = { [] }
    var stubborn: Set<pid_t> = []
    private(set) var matchingIdentifier: [Bool] = []
    private(set) var terminated: [pid_t] = []
    private(set) var forced: [Bool] = []
    private var exited: Set<pid_t> = []

    func running(for app: InstalledApp, matchingIdentifier: Bool) -> [RunningProcess] {
        self.matchingIdentifier.append(matchingIdentifier)
        return next()
    }

    func terminate(_ process: RunningProcess, force: Bool) {
        terminated.append(process.pid)
        forced.append(force)
        if !stubborn.contains(process.pid) { exited.insert(process.pid) }
    }

    func hasExited(_ process: RunningProcess) -> Bool { exited.contains(process.pid) }
}

/// Records the arguments of each launchctl call, optionally holding the first
/// one back so a test can look at the model while it waits.
final class FakeLaunchControl: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    private let delay: UInt64

    init(delay: UInt64 = 0) { self.delay = delay }

    var calls: [[String]] {
        lock.withLock { recorded }
    }

    func run(_ arguments: [String]) async -> ProcessResult? {
        lock.withLock { recorded.append(arguments) }
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        return nil
    }
}

@MainActor
final class UninstallerViewModelTests: XCTestCase {
    private var tree: TemporaryTree!
    private var home: FakeHome!
    private var defaults: UserDefaults!
    private var suite: String!
    private let processes = FakeProcessControl()

    override func setUpWithError() throws {
        tree = try TemporaryTree()
        home = try FakeHome(tree: tree)
        suite = "TwanCleanTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        home = nil
        tree = nil
    }

    private func makeModel(launch: FakeLaunchControl = FakeLaunchControl()) throws -> UninstallerViewModel {
        let home = home!
        return UninstallerViewModel(
            index: InstalledAppIndex(roots: [home.url("Applications")]),
            makeFinder: { LeftoverFinder(home: home.home, policy: home.policy, systemFolders: []) },
            removal: try home.removalService(), sizeCache: nil, processes: processes,
            launchctl: { await launch.run($0) }, timing: .immediate, defaults: defaults)
    }

    @discardableResult
    private func install(_ file: String, id: String, name: String) throws -> URL {
        try tree.makeAppBundle("home/Applications/\(file).app", bundleIdentifier: id, name: name)
    }

    private func leftoverNames(_ model: UninstallerViewModel) -> Set<String> {
        Set((model.leftovers?.items ?? []).map(\.name))
    }

    // MARK: - Finder Service

    func testAServiceRequestScansOnlyOnceEveryInstalledAppIsKnown() async throws {
        let notion = try install("Notion", id: "notion.id", name: "Notion")
        try install("Notion Calendar", id: "com.cron.electron", name: "Notion Calendar")
        try tree.makeFile("home/Library/Application Support/Notion/state", bytes: 4_096)
        try tree.makeFile("home/Library/Application Support/Notion Calendar/state", bytes: 4_096)
        let model = try makeModel()

        // Twan Clean was not showing the app list when the service was used.
        XCTAssertEqual(model.selectApp(at: notion, policy: home.policy), .selected)
        await model.findTask?.value

        XCTAssertEqual(model.apps.count, 2)
        XCTAssertTrue(leftoverNames(model).contains("Notion"))
        XCTAssertFalse(leftoverNames(model).contains("Notion Calendar"))
    }

    func testAServiceRequestForAnAppTheListMissesStaysSelected() async throws {
        let deep = try tree.makeAppBundle("home/Applications/A/B/C/D/Deep.app", bundleIdentifier: "com.example.deep",
                                          name: "Deep")
        let model = try makeModel()

        XCTAssertEqual(model.selectApp(at: deep, policy: home.policy), .selected)
        await model.findTask?.value
        await model.waitForAppList()

        XCTAssertEqual(model.selectedApp?.bundleIdentifier, "com.example.deep")
        XCTAssertEqual(model.apps.map(\.bundleIdentifier), ["com.example.deep"])
    }

    func testAServiceRequestForALinkOrAProtectedAppSaysWhy() throws {
        let real = try tree.makeAppBundle("home/Shared/Riot Client.app", bundleIdentifier: "com.example.riot")
        let link = try tree.makeSymlink("home/Applications/Client Riot.app", to: real)
        let safari = try install("Safari", id: "com.apple.Safari", name: "Safari")
        let outside = try tree.makeAppBundle("home/Downloads/Loose.app", bundleIdentifier: "com.example.loose")
        let model = try makeModel()

        XCTAssertEqual(model.selectApp(at: link, policy: home.policy), .rejected(.symbolicLink(name: "Client Riot")))
        XCTAssertEqual(model.selectApp(at: safari, policy: home.policy), .rejected(.protectedApp(name: "Safari")))
        XCTAssertEqual(model.selectApp(at: outside, policy: home.policy), .rejected(.outsideApplications(name: "Loose")))
        XCTAssertNil(model.selectedApp)
    }

    func testAServiceRequestWithSeveralAppsOpensTheFirstOneThatCanBeUninstalled() async throws {
        let real = try tree.makeAppBundle("home/Shared/Riot Client.app", bundleIdentifier: "com.example.riot")
        let link = try tree.makeSymlink("home/Applications/Client Riot.app", to: real)
        let editor = try install("Editor", id: "com.example.editor", name: "Editor")
        let model = try makeModel()

        XCTAssertEqual(model.selectApp(from: [link, editor], policy: home.policy), .selected)
        await model.findTask?.value
        XCTAssertEqual(model.selectedApp?.bundleIdentifier, "com.example.editor")

        XCTAssertEqual(model.selectApp(from: [link], policy: home.policy), .rejected(.symbolicLink(name: "Client Riot")))
        XCTAssertEqual(model.selectApp(from: [], policy: home.policy), .rejected(.noApplication))
    }

    func testAServiceRequestWhileUninstallingIsRefusedWithAReason() async throws {
        let editor = try install("Editor", id: "com.example.editor", name: "Editor")
        let other = try install("Other", id: "com.example.other", name: "Other")
        try writeAgent(label: "com.example.editor.agent", in: editor)
        let launch = FakeLaunchControl(delay: 300_000_000)
        let model = try makeModel(launch: launch)
        model.selectApp(at: editor, policy: home.policy)
        await model.findTask?.value
        let app = try XCTUnwrap(model.selectedApp)
        let items = model.selectedItems

        let uninstalling = Task { await model.uninstall(items, of: app) }
        for _ in 0..<500 where model.phase != .uninstalling { await Task.yield() }
        XCTAssertEqual(model.phase, .uninstalling)

        XCTAssertEqual(model.selectApp(at: other, policy: home.policy), .rejected(.busy))
        await uninstalling.value
        XCTAssertEqual(model.selectedApp?.bundleIdentifier, "com.example.editor")
    }

    // MARK: - Agents bundled in the app

    private func writeAgent(label: String, in app: URL, file: String = "agent.plist") throws {
        let folder = app.appendingPathComponent("Contents/Library/LaunchAgents")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: ["Label": label], format: .xml, options: 0)
        try data.write(to: folder.appendingPathComponent(file))
    }

    func testAgentsRegisteredInsideTheBundleAreStoppedBeforeTheAppIsRemoved() async throws {
        let editor = try install("Editor", id: "com.example.editor", name: "Editor")
        try writeAgent(label: "com.example.editor.agent", in: editor)
        try writeAgent(label: "com.apple.Dock.agent", in: editor, file: "apple.plist")
        try writeAgent(label: "../../etc/evil", in: editor, file: "path.plist")
        let launch = FakeLaunchControl()
        let model = try makeModel(launch: launch)
        model.selectApp(at: editor, policy: home.policy)
        await model.findTask?.value
        let app = try XCTUnwrap(model.selectedApp)

        await model.uninstall(model.selectedItems, of: app)

        XCTAssertEqual(launch.calls, [["bootout", "gui/\(getuid())/com.example.editor.agent"]])
        XCTAssertFalse(tree.exists(editor), "the app is in the Trash")
        XCTAssertNil(model.outcome?.failures.first)
    }

    func testUninstallingShowsEachStageInOrderAndClearsItWhenDone() async throws {
        let editor = try install("Editor", id: "com.example.editor", name: "Editor")
        try writeAgent(label: "com.example.editor.agent", in: editor)
        var looks = 0
        processes.next = {
            looks += 1
            return looks == 1 ? [RunningProcess(pid: 101, name: "Editor")] : []
        }
        let model = try makeModel()
        model.selectApp(at: editor, policy: home.policy)
        await model.findTask?.value
        let app = try XCTUnwrap(model.selectedApp)
        let items = model.selectedItems
        let log = RemovalProgressLog(model.$removalProgress)

        await model.uninstall(items, of: app)

        XCTAssertEqual(log.stages, [.stoppingServices, .quittingApp("Editor"), .movingToTrash])
        XCTAssertEqual(log.shown.first?.total, items.count)
        XCTAssertNil(model.removalProgress)
        XCTAssertTrue(log.endedEmpty)
        XCTAssertEqual(model.phase, .idle)
    }

    func testProgressIsClearedWhenTheAppWillNotQuit() async throws {
        try install("Editor", id: "com.example.editor", name: "Editor")
        processes.stubborn = [301]
        processes.next = { [RunningProcess(pid: 301, name: "Editor")] }
        let model = try makeModel()
        let log = RemovalProgressLog(model.$removalProgress)

        _ = try await uninstallEditor(model)

        XCTAssertEqual(log.stages, [.stoppingServices, .quittingApp("Editor")])
        XCTAssertNil(model.removalProgress)
        XCTAssertEqual(model.phase, .idle)
    }

    func testSearchingForLeftoversReportsWhereItIsLookingAndWhenItStarted() async throws {
        let editor = try install("Editor", id: "com.example.editor", name: "Editor")
        try tree.makeFile("home/Library/Application Support/Editor/state", bytes: 4_096)
        let model = try makeModel()
        XCTAssertNil(model.leftoverSearchStarted)

        model.selectApp(at: editor, policy: home.policy)
        XCTAssertNotNil(model.leftoverSearchStarted)
        await model.findTask?.value

        let path = try XCTUnwrap(model.leftoverProgress.currentPath)
        XCTAssertTrue(path.hasPrefix(home.home.path), path)
        XCTAssertFalse(model.isFindingLeftovers)
    }

    func testOnlyAnAppsOwnAgentLabelsAreStopped() {
        XCTAssertTrue(UninstallerViewModel.isStoppable(label: "com.example.editor.agent"))
        XCTAssertFalse(UninstallerViewModel.isStoppable(label: "com.apple.Dock.agent"))
        XCTAssertFalse(UninstallerViewModel.isStoppable(label: ""))
        XCTAssertFalse(UninstallerViewModel.isStoppable(label: "a/b"))
        XCTAssertFalse(UninstallerViewModel.isStoppable(label: "a b"))
    }

    // MARK: - Quitting

    private func uninstallEditor(_ model: UninstallerViewModel, force: Bool = false) async throws -> URL {
        let editor = tree.url("home/Applications/Editor.app")
        model.selectApp(at: editor, policy: home.policy)
        await model.findTask?.value
        let app = try XCTUnwrap(model.selectedApp)
        await model.uninstall(model.selectedItems, of: app, forceQuit: force)
        return editor
    }

    func testAHelperThatLaunchdStartsAgainIsQuitToo() async throws {
        try install("Editor", id: "com.example.editor", name: "Editor")
        var looks = 0
        processes.next = {
            looks += 1
            switch looks {
            case 1: return [RunningProcess(pid: 101, name: "Editor")]
            case 2: return [RunningProcess(pid: 102, name: "Editor Helper")]
            default: return []
            }
        }
        let model = try makeModel()

        let editor = try await uninstallEditor(model)

        XCTAssertEqual(processes.terminated, [101, 102])
        XCTAssertFalse(tree.exists(editor))
        XCTAssertNil(model.outcome?.failures.first)
    }

    func testAHelperThatKeepsComingBackStopsTheUninstall() async throws {
        try install("Editor", id: "com.example.editor", name: "Editor")
        var pid: pid_t = 200
        processes.next = {
            pid += 1
            return [RunningProcess(pid: pid, name: "Editor Helper")]
        }
        let model = try makeModel()

        let editor = try await uninstallEditor(model)

        XCTAssertTrue(tree.exists(editor), "nothing was removed")
        XCTAssertTrue(try XCTUnwrap(model.outcome?.failures.first).message.contains("Editor Helper"))
    }

    func testAProcessThatWillNotQuitStopsTheUninstall() async throws {
        try install("Editor", id: "com.example.editor", name: "Editor")
        processes.stubborn = [301]
        processes.next = { [RunningProcess(pid: 301, name: "Editor")] }
        let model = try makeModel()

        let editor = try await uninstallEditor(model, force: true)

        XCTAssertTrue(tree.exists(editor))
        XCTAssertEqual(processes.forced, [true])
        XCTAssertNotNil(model.outcome?.failures.first)
    }

    func testProcessesAreMatchedByPathNotIdentifierWhileAnotherCopyIsInstalled() async throws {
        try install("Editor", id: "com.example.editor", name: "Editor")
        try tree.makeAppBundle("home/Applications/Old/Editor.app", bundleIdentifier: "com.example.editor", name: "Editor")
        let model = try makeModel()
        model.loadAppsIfNeeded()
        await model.waitForAppList()
        processes.next = { [] }

        _ = try await uninstallEditor(model)
        XCTAssertEqual(Set(processes.matchingIdentifier), [false])
        XCTAssertEqual(model.apps.count, 1, "only the removed copy left the list")
    }

    func testProcessesAreMatchedByIdentifierForASingleCopy() async throws {
        try install("Editor", id: "com.example.editor", name: "Editor")
        processes.next = { [] }
        let model = try makeModel()

        _ = try await uninstallEditor(model)

        XCTAssertEqual(Set(processes.matchingIdentifier), [true])
    }

    // MARK: - Recycled process ids

    func testAProcessIsOnlySignalledWhileItIsStillTheOneThatWasFound() throws {
        var signals: [(pid_t, Int32)] = []
        let control = SystemAppProcessControl(send: { signals.append(($0, $1)) })
        let pid = getpid()
        let identity = try XCTUnwrap(ProcessIdentity.of(pid))

        control.terminate(RunningProcess(pid: pid, name: "same", identity: identity), force: false)
        control.terminate(RunningProcess(pid: pid, name: "forced", identity: identity), force: true)
        XCTAssertEqual(signals.map(\.1), [SIGTERM, SIGKILL])

        signals = []
        let recycled = ProcessIdentity(path: identity.path, startSeconds: identity.startSeconds - 100,
                                       startMicroseconds: identity.startMicroseconds)
        let otherProgram = ProcessIdentity(path: "/bin/sleep", startSeconds: identity.startSeconds,
                                           startMicroseconds: identity.startMicroseconds)
        control.terminate(RunningProcess(pid: pid, name: "recycled", identity: recycled), force: true)
        control.terminate(RunningProcess(pid: pid, name: "other", identity: otherProgram), force: true)
        control.terminate(RunningProcess(pid: pid, name: "unknown"), force: true)
        XCTAssertTrue(signals.isEmpty)
    }

    func testAProcessWhoseIdentityChangedCountsAsExited() throws {
        let control = SystemAppProcessControl(send: { _, _ in })
        let pid = getpid()
        let identity = try XCTUnwrap(ProcessIdentity.of(pid))

        XCTAssertFalse(control.hasExited(RunningProcess(pid: pid, name: "me", identity: identity)))
        let recycled = ProcessIdentity(path: "/bin/sleep", startSeconds: 1, startMicroseconds: 0)
        XCTAssertTrue(control.hasExited(RunningProcess(pid: pid, name: "gone", identity: recycled)))
    }

    // MARK: - Cancellation

    func testCancellingTheAwaitingTaskCancelsTheDetachedWork() async {
        let task = Task { () -> Bool in
            await runDetached {
                let deadline = Date().addingTimeInterval(5)
                while !Task.isCancelled, Date() < deadline { usleep(1_000) }
                return Task.isCancelled
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        let sawCancellation = await task.value
        XCTAssertTrue(sawCancellation)
    }
}
