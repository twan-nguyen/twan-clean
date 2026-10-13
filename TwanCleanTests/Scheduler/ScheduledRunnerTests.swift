import XCTest
@testable import TwanClean

final class ScheduledRunnerTests: XCTestCase {
    private var tree: TemporaryTree!
    private var home: FakeHome!
    private var store: ScheduleStore!
    private let now = Date()

    override func setUpWithError() throws {
        tree = try TemporaryTree()
        home = try FakeHome(tree: tree)
        store = ScheduleStore(folder: tree.url("support"))
        try tree.makeFile("home/Library/Caches/com.example.editor/cache.db", bytes: 50_000)
        try tree.makeFile("home/Library/Caches/com.apple.Safari/cache.db", bytes: 50_000)
        try tree.makeFile("home/Library/Caches/com.example.running/cache.db", bytes: 50_000)
    }

    override func tearDown() {
        store = nil
        home = nil
        tree = nil
    }

    private func runner(notified: NotificationLog = NotificationLog(),
                        scanners: [any CategoryScanner] = [UserCacheScanner()],
                        lockFile: URL? = nil) -> ScheduledRunner {
        let homeURL = home.home
        let policy = home.policy
        return ScheduledRunner(
            store: store,
            coordinator: SmartScanCoordinator(scanners: scanners),
            removal: RemovalService(policy: policy),
            lockFile: lockFile ?? tree.url("support/scan.lock"),
            makeContext: {
                ScanContext(home: homeURL, policy: policy, commands: CommandRunner(searchPaths: [], timeout: 1),
                            runningBundleIDs: ["com.example.running"])
            },
            notify: { summary, _ in await notified.record(summary) })
    }

    private func schedule(_ action: ScheduleSettings.Action, minimum: Int64 = 0, lastRun: Date? = nil) throws {
        var settings = ScheduleSettings()
        settings.isEnabled = true
        settings.hour = 0
        settings.action = action
        settings.categories = [.userCache]
        settings.minimumBytesToClean = minimum
        settings.lastRun = lastRun
        try store.save(settings)
    }

    func testDoesNothingWhenNotDue() async throws {
        try schedule(.clean, lastRun: now)
        let outcome = await runner().run(now: now)
        XCTAssertEqual(outcome, .notDue)
        XCTAssertTrue(tree.exists(home.url("Library/Caches/com.example.editor")))
    }

    func testCleansOnlySafePreselectedItems() async throws {
        try schedule(.clean)
        let log = NotificationLog()

        guard case .ran(let summary) = await runner(notified: log).run(now: now) else { return XCTFail("did not run") }

        XCTAssertFalse(tree.exists(home.url("Library/Caches/com.example.editor")))
        XCTAssertTrue(tree.exists(home.url("Library/Caches/com.apple.Safari")))
        XCTAssertTrue(tree.exists(home.url("Library/Caches/com.example.running")))
        XCTAssertGreaterThan(summary.cleanedBytes, 0)
        let notifications = await log.summaries
        XCTAssertEqual(notifications.count, 1)
        // Stored as ISO 8601, which keeps whole seconds.
        XCTAssertEqual(store.loadSettings().lastRun?.timeIntervalSince1970 ?? 0, now.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(store.loadSummary()?.cleanedBytes, summary.cleanedBytes)
    }

    func testNotifyModeNeverRemovesAnything() async throws {
        try schedule(.notify)
        guard case .ran(let summary) = await runner().run(now: now) else { return XCTFail("did not run") }
        XCTAssertEqual(summary.cleanedBytes, 0)
        XCTAssertGreaterThan(summary.foundBytes, 0)
        XCTAssertTrue(tree.exists(home.url("Library/Caches/com.example.editor")))
    }

    func testBelowTheMinimumNothingIsCleaned() async throws {
        try schedule(.clean, minimum: 10_000_000_000)
        _ = await runner().run(now: now)
        XCTAssertTrue(tree.exists(home.url("Library/Caches/com.example.editor")))
    }

    func testSkipsWhileTheAppHoldsTheLock() async throws {
        try schedule(.clean)
        let held = try XCTUnwrap(RunLock.acquire(at: tree.url("support/scan.lock")))
        let outcome = await runner().run(now: now)
        XCTAssertEqual(outcome, .busy)
        XCTAssertTrue(tree.exists(home.url("Library/Caches/com.example.editor")))
        withExtendedLifetime(held) {}
    }

    private func item(_ purpose: RemovalPurpose, category: CleanupCategoryID = .userCache,
                      admin: Bool = false, selected: Bool = true) -> CleanableItem {
        CleanableItem(url: URL(fileURLWithPath: "/x/\(UUID())"), category: category,
                      identity: FileIdentity(device: 1, inode: 1), isDirectory: true, bytes: 1,
                      purpose: purpose, requiresAdministrator: admin, selectedByDefault: selected,
                      lastModified: nil, notes: [])
    }

    func testAutomaticCleaningExcludesPasswordsUserFilesAndUnselectedItems() {
        let result = CategoryResult(category: .userCache, items: [
            item(.regenerableCache), item(.regenerableCache, admin: true), item(.regenerableCache, selected: false),
            item(.userFile), item(.buildArchive),
        ])
        XCTAssertEqual(ScheduledRunner.automaticallyCleanable([result]).count, 1)
    }

    func testAutomaticCleaningNeverTakesTrashContentsOrMail() {
        let results = [
            CategoryResult(category: .trash, items: [item(.trashContents, category: .trash)]),
            CategoryResult(category: .mail, items: [item(.regenerableCache, category: .mail)]),
            CategoryResult(category: .xcode, items: [item(.regenerableCache, category: .xcode)]),
        ]
        XCTAssertEqual(ScheduledRunner.automaticallyCleanable(results).map(\.category), [.xcode])
    }

    func testCleanRunLeavesTheTrashAndMailDownloadsAlone() async throws {
        try tree.makeFile("home/.Trash/old-report.pdf", bytes: 50_000)
        try tree.makeFile("home/Library/Mail Downloads/edited-attachment.docx", bytes: 50_000)
        var settings = ScheduleSettings()
        settings.isEnabled = true
        settings.hour = 0
        settings.action = .clean
        settings.categories = [.userCache, .trash, .mail]
        settings.minimumBytesToClean = 0
        try store.save(settings)

        let outcome = await runner(scanners: [UserCacheScanner(), TrashScanner(), MailAttachmentsScanner()]).run(now: now)

        guard case .ran(let summary) = outcome else { return XCTFail("did not run") }
        XCTAssertGreaterThan(summary.foundBytes, 100_000)
        XCTAssertTrue(tree.exists(home.url(".Trash/old-report.pdf")))
        XCTAssertTrue(tree.exists(home.url("Library/Mail Downloads/edited-attachment.docx")))
        XCTAssertFalse(tree.exists(home.url("Library/Caches/com.example.editor")))
    }

    func testFailedScanRecordsNothingAndSaysNothing() async throws {
        try schedule(.clean)
        let log = NotificationLog()

        let outcome = await runner(notified: log, scanners: [FailingScanner()]).run(now: now)

        XCTAssertEqual(outcome, .scanFailed)
        XCTAssertNil(store.loadSettings().lastRun)
        XCTAssertNil(store.loadSummary())
        let notifications = await log.summaries
        XCTAssertTrue(notifications.isEmpty)
    }

    func testAttemptIsRecordedBeforeTheScanSoAnInterruptedRunIsNotRepeatedHourly() async throws {
        try schedule(.notify)
        let probe = LastRunProbe(store: store)

        _ = await runner(scanners: [probe]).run(now: now)

        let seen = await probe.seen.date
        XCTAssertEqual(seen?.timeIntervalSince1970 ?? 0, now.timeIntervalSince1970, accuracy: 1)
    }

    func testUnreadableScheduleFileStopsTheRunWithoutOverwritingIt() async throws {
        try tree.makeDirectory("support")
        let file = tree.url("support/schedule.json")
        try Data("{ not json".utf8).write(to: file)

        let outcome = await runner().run(now: now)

        XCTAssertEqual(outcome, .settingsUnreadable)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "{ not json")
    }

    func testLockFileThatCannotBeOpenedIsNotReportedAsBusy() async throws {
        try schedule(.clean)
        let directoryInTheWay = try tree.makeDirectory("support/scan.lock")

        let outcome = await runner(lockFile: directoryInTheWay).run(now: now)

        XCTAssertEqual(outcome, .lockUnavailable)
        XCTAssertTrue(tree.exists(home.url("Library/Caches/com.example.editor")))
    }
}

private struct FailingScanner: CategoryScanner {
    let category = CleanupCategoryID.userCache

    func scan(_ context: ScanContext) async throws -> CategoryResult {
        throw CocoaError(.fileReadUnknown)
    }
}

/// Records what the schedule file says about the last run while a scan is in progress.
private struct LastRunProbe: CategoryScanner {
    actor Seen {
        private(set) var date: Date?
        func record(_ date: Date?) { self.date = date }
    }

    let category = CleanupCategoryID.userCache
    let store: ScheduleStore
    let seen = Seen()

    func scan(_ context: ScanContext) async throws -> CategoryResult {
        await seen.record(store.loadSettings().lastRun)
        return CategoryResult(category: category, items: [])
    }
}

actor NotificationLog {
    private(set) var summaries: [ScheduledRunSummary] = []

    func record(_ summary: ScheduledRunSummary) {
        summaries.append(summary)
    }
}
