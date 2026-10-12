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
        let running = await MainActor.run {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        }
        return ScanContext(settings: ScanSettings.load(), runningBundleIDs: running,
                           protectedLocations: ProtectedLocations.current())
    }

    enum Outcome: Equatable {
        case notDue
        /// The app or another run is scanning right now.
        case busy
        case ran(ScheduledRunSummary)
    }

    @discardableResult
    func run(now: Date = Date()) async -> Outcome {
        var settings = store.loadSettings()
        guard settings.isDue(now: now) else { return .notDue }
        guard let lock = RunLock.acquire(at: lockFile) else { return .busy }
        defer { withExtendedLifetime(lock) {} }

        let context = await makeContext()
        let categories = settings.categories.filter(ScheduleSettings.schedulableCategories.contains)
        let results = (try? await coordinator.scan(categories, context: context)) ?? []
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
        settings.lastRun = now
        try? store.save(settings)
        try? store.save(summary)
        await notify(summary, settings.action)
        return .ran(summary)
    }

    /// Only what a person would clean without looking: items the scan
    /// preselects, regenerable data that is deleted rather than trashed, and
    /// nothing that needs a password.
    static func automaticallyCleanable(_ results: [CategoryResult]) -> [CleanableItem] {
        results.flatMap(\.items).filter { item in
            item.selectedByDefault
                && !item.requiresAdministrator
                && (item.purpose == .regenerableCache || item.purpose == .trashContents)
        }
    }
}
