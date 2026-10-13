import AppKit

/// The background run the LaunchAgent starts every hour. It does nothing
/// unless a run is due, then scans the chosen categories and, if the user
/// asked for it, cleans the items that are always safe to clean.
struct ScheduledRunner: Sendable {
    let store: ScheduleStore
    let coordinator: SmartScanCoordinator
    let removal: RemovalService
    let lockFile: URL
    let makeContext: @Sendable () async -> ScanContext
    let notify: @Sendable (ScheduledRunSummary, ScheduleSettings.Action) async -> Void

    init(store: ScheduleStore = ScheduleStore(),
         coordinator: SmartScanCoordinator = SmartScanCoordinator(),
         removal: RemovalService = RemovalService(),
         lockFile: URL = RunLock.defaultFile,
         makeContext: @escaping @Sendable () async -> ScanContext = ScheduledRunner.liveContext,
         notify: @escaping @Sendable (ScheduledRunSummary, ScheduleSettings.Action) async -> Void = NotificationService.post) {
        self.store = store
        self.coordinator = coordinator
        self.removal = removal
        self.lockFile = lockFile
        self.makeContext = makeContext
        self.notify = notify
    }

    static let liveContext: @Sendable () async -> ScanContext = {
        let running = await MainActor.run { RunningApp.current() }
        return ScanContext(settings: ScanSettings.load(), runningApps: running,
                           protectedLocations: ProtectedLocations.current())
    }

    /// A scheduled run taking longer than this is stopped.
    static let timeLimit: TimeInterval = 30 * 60

    enum Outcome: Equatable {
        case notDue
        /// The app or another run is scanning right now.
        case busy
        case ran(ScheduledRunSummary)
        /// The schedule file exists but cannot be read. Nothing runs until
        /// the app has dealt with it.
        case settingsUnreadable
        /// The lock file cannot be created, so a clash with the app cannot be ruled out.
        case lockUnavailable
        /// The scan itself failed. Nothing was recorded, so the next check tries again.
        case scanFailed

        /// What the process reports to launchd.
        var exitStatus: Int32 {
            switch self {
            case .notDue, .busy, .ran: EXIT_SUCCESS
            case .settingsUnreadable, .lockUnavailable, .scanFailed: EXIT_FAILURE
            }
        }
    }

    @discardableResult
    func run(now: Date = Date()) async -> Outcome {
        let settings: ScheduleSettings
        do {
            settings = try store.loadSettingsChecked()
        } catch {
            SchedulerLog.logger.error("Schedule file is unreadable: \(error.localizedDescription, privacy: .public)")
            return .settingsUnreadable
        }
        guard settings.isDue(now: now) else { return .notDue }

        let lock: RunLock
        switch RunLock.attempt(at: lockFile) {
        case .acquired(let acquired):
            lock = acquired
        case .busy:
            return .busy
        case .unavailable(let reason):
            SchedulerLog.logger.error("Scan lock unavailable: \(reason, privacy: .public)")
            return .lockUnavailable
        }
        defer { withExtendedLifetime(lock) {} }

        // Mark the attempt before the slow part. A scan that is stopped for
        // taking too long never gets to record itself, and would otherwise
        // start over from scratch at every hourly check.
        record(lastRun: now)

        let context = await makeContext()
        let categories = settings.categories.filter(ScheduleSettings.schedulableCategories.contains)
        let results: [CategoryResult]
        do {
            results = try await coordinator.scan(categories, context: context)
        } catch {
            // Give the attempt back: nothing was found, so nothing is reported.
            SchedulerLog.logger.error("Scheduled scan failed: \(error.localizedDescription, privacy: .public)")
            record(lastRun: settings.lastRun)
            return .scanFailed
        }
        let found = results.reduce(0) { $0 + $1.totalBytes }

        var report = RemovalReport()
        if settings.action == .clean {
            let items = Self.automaticallyCleanable(results)
            if items.reduce(0, { $0 + $1.bytes }) >= settings.minimumBytesToClean {
                report = await removal.remove(items.map(\.removalRequest))
            }
        }

        let summary = ScheduledRunSummary(
            date: now, foundBytes: found, cleanedBytes: report.freedBytes,
            failedCount: report.failed.count + report.refused.count + report.needsAdministrator.count,
            lockedCount: results.reduce(0) { $0 + $1.unreadableLocations.count })
        record(lastRun: now)
        do {
            try store.save(summary)
        } catch {
            SchedulerLog.logger.error("Could not save the run summary: \(error.localizedDescription, privacy: .public)")
        }
        await notify(summary, settings.action)
        return .ran(summary)
    }

    /// Reloads before saving: the user may have changed the schedule while
    /// the scan ran, and only the time of the run is ours to record. A file
    /// that cannot be read is left alone rather than overwritten.
    private func record(lastRun: Date?) {
        do {
            var latest = try store.loadSettingsChecked()
            latest.lastRun = lastRun
            try store.save(latest)
        } catch {
            SchedulerLog.logger.error("Could not record the run time: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Only what a person would clean without looking: items the scan
    /// preselects, regenerable data that is deleted rather than trashed, and
    /// nothing that needs a password. The Trash and Mail attachments are left
    /// out even though they are deleted outright when cleaned by hand: Mail
    /// can hold an attachment edited in place, and the Trash is the user's
    /// last chance to recover something.
    static func automaticallyCleanable(_ results: [CategoryResult]) -> [CleanableItem] {
        results.flatMap(\.items).filter { item in
            item.selectedByDefault
                && !item.requiresAdministrator
                && item.purpose == .regenerableCache
                && item.category != .mail
        }
    }
}
