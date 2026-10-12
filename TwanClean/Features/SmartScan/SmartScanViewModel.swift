import AppKit
import Combine

/// What a cleanup run achieved, shown to the user afterwards.
struct CleanupOutcome: Identifiable {
    struct Failure: Identifiable {
        let id = UUID()
        let name: String
        let message: String
    }

    let id = UUID()
    var freedBytes: Int64 = 0
    var removedCount = 0
    var failures: [Failure] = []
    /// Blocked by permissions; the user may retry with the administrator
    /// password, or grant Full Disk Access first.
    var needsAdministrator: [RemovalRequest] = []

    init(_ report: RemovalReport) {
        add(report)
    }

    mutating func add(_ report: RemovalReport) {
        freedBytes += report.freedBytes
        removedCount += report.removed.count
        failures += report.failed.map { failure in
            // macOS also guards apps themselves: moving one needs the App
            // Management permission, which only the user can grant.
            let hint = failure.request.purpose == .appBundle
                ? " " + String(localized: "Allow Twan Clean in Privacy & Security › App Management.")
                : ""
            return Failure(name: failure.request.url.lastPathComponent, message: failure.message + hint)
        }
        failures += report.refused.map {
            Failure(name: $0.request.url.lastPathComponent, message: $0.reason.localizedDescription)
        }
        needsAdministrator = report.needsAdministrator
    }
}

extension RefusalReason {
    var localizedDescription: String {
        switch self {
        case .notAFileURL, .unresolvable: String(localized: "The item could not be found.")
        case .protectedRoot, .systemLocation: String(localized: "This location is protected and is never removed.")
        case .outsideAllowedArea: String(localized: "This location is outside what Twan Clean may remove.")
        case .appleItem: String(localized: "Items belonging to macOS are never removed.")
        case .notAnAppBundle: String(localized: "The item is not an application.")
        case .changedSinceScan: String(localized: "The item changed after the scan. Scan again to review it.")
        case .mountPoint: String(localized: "The item is a separate disk and is never removed.")
        }
    }
}

@MainActor
final class SmartScanViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning
        case ready
        case cleaning
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var results: [CleanupCategoryID: CategoryResult] = [:]
    @Published private(set) var scanningCategories: Set<CleanupCategoryID> = []
    @Published private(set) var finishedCount = 0
    @Published private(set) var lastScanDate: Date?
    @Published var selection: Set<String> = []
    @Published var outcome: CleanupOutcome?
    /// Shown when a scheduled run is busy and the request must wait.
    @Published var notice: String?

    let progress = ScanProgressReporter()
    private let coordinator: SmartScanCoordinator
    private let removal: RemovalService
    private let makeContext: @MainActor (ScanProgressReporter) -> ScanContext
    private let runLockFile: URL?
    private var scanTask: Task<Void, Never>?

    init(coordinator: SmartScanCoordinator = SmartScanCoordinator(),
         removal: RemovalService = RemovalService(),
         makeContext: @escaping @MainActor (ScanProgressReporter) -> ScanContext = SmartScanViewModel.liveContext,
         runLockFile: URL? = RunLock.defaultFile) {
        self.coordinator = coordinator
        self.removal = removal
        self.makeContext = makeContext
        self.runLockFile = runLockFile
    }

    /// Takes the lock shared with the scheduled run, or explains why not.
    private func takeRunLock() -> (granted: Bool, lock: RunLock?) {
        guard let runLockFile else { return (true, nil) }
        guard let lock = RunLock.acquire(at: runLockFile) else {
            notice = String(localized: "A scheduled scan is running. Try again in a moment.")
            return (false, nil)
        }
        return (true, lock)
    }

    /// The real home folder, the saved settings and the apps running now.
    static func liveContext(progress: ScanProgressReporter) -> ScanContext {
        ScanContext(
            settings: ScanSettings.load(),
            runningBundleIDs: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),
            progress: progress,
            protectedLocations: ProtectedLocations.current())
    }

    // MARK: - Scanning

    var isScanning: Bool { phase == .scanning }

    func scan(_ categories: [CleanupCategoryID] = CleanupCategoryID.allCases) {
        startScan(categories)
    }

    /// Starts a scan and returns its task, so callers that need the result,
    /// such as tests, can wait for it.
    @discardableResult
    func startScan(_ categories: [CleanupCategoryID]) -> Task<Void, Never>? {
        guard phase != .scanning, phase != .cleaning else { return nil }
        let runLock = takeRunLock()
        guard runLock.granted else { return nil }
        phase = .scanning
        scanningCategories = Set(categories)
        finishedCount = 0
        let context = makeContext(progress)

        scanTask = Task { [coordinator] in
            do {
                let scanned = try await coordinator.scan(categories, context: context) { _ in
                    await MainActor.run { self.finishedCount += 1 }
                }
                self.apply(scanned, replacing: Set(categories))
            } catch {
                // Cancelled: keep whatever was there before.
            }
            self.scanningCategories = []
            self.phase = self.results.isEmpty ? .idle : .ready
            withExtendedLifetime(runLock.lock) {}
        }
        return scanTask
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    private func apply(_ scanned: [CategoryResult], replacing categories: Set<CleanupCategoryID>) {
        // Re-scanning a few categories must still settle overlaps with the
        // categories kept from the previous scan.
        let kept = results.values.filter { !categories.contains($0.category) }
        let merged = SmartScanCoordinator.resolveOverlaps(kept + scanned)
        results = Dictionary(uniqueKeysWithValues: merged.map { ($0.category, $0) })

        let scannedIDs = Set(scanned.flatMap { $0.items.map(\.id) })
        let liveIDs = Set(merged.flatMap { $0.items.map(\.id) })
        selection = selection.subtracting(scannedIDs).intersection(liveIDs)
            .union(merged.flatMap(\.items).filter { scannedIDs.contains($0.id) && $0.selectedByDefault }.map(\.id))
        lastScanDate = Date()
    }

    // MARK: - Selection

    func items(in category: CleanupCategoryID) -> [CleanableItem] {
        results[category]?.items ?? []
    }

    func selectedItems(in categories: Set<CleanupCategoryID>? = nil) -> [CleanableItem] {
        results.values
            .filter { categories?.contains($0.category) ?? true }
            .flatMap(\.items)
            .filter { selection.contains($0.id) }
    }

    func selectedBytes(in categories: Set<CleanupCategoryID>? = nil) -> Int64 {
        selectedItems(in: categories).reduce(0) { $0 + $1.bytes }
    }

    var totalFoundBytes: Int64 {
        results.values.reduce(0) { $0 + $1.totalBytes }
    }

    func isSelected(_ item: CleanableItem) -> Bool {
        selection.contains(item.id)
    }

    func setSelected(_ item: CleanableItem, _ selected: Bool) {
        if selected { selection.insert(item.id) } else { selection.remove(item.id) }
    }

    func setAllSelected(in category: CleanupCategoryID, _ selected: Bool) {
        let ids = items(in: category).map(\.id)
        if selected { selection.formUnion(ids) } else { selection.subtract(ids) }
    }

    // MARK: - Cleaning

    func clean(_ categories: Set<CleanupCategoryID>? = nil) async {
        let items = selectedItems(in: categories)
        guard !items.isEmpty, phase == .ready else { return }
        let runLock = takeRunLock()
        guard runLock.granted else { return }
        phase = .cleaning
        let report = await removal.remove(items.map(\.removalRequest))
        finishCleaning(report, into: CleanupOutcome(report))
        withExtendedLifetime(runLock.lock) {}
    }

    /// Retries what permissions blocked, after the administrator prompt. The
    /// outcome is passed in because its sheet is already closed by then.
    func retryWithAdministrator(_ outcome: CleanupOutcome) async {
        guard !outcome.needsAdministrator.isEmpty, phase == .ready else { return }
        var current = outcome
        phase = .cleaning
        let remover = PrivilegedRemover(
            service: removal,
            prompt: String(localized: "Twan Clean needs your password to remove the selected items."))
        let report = await remover.remove(current.needsAdministrator)
        current.add(report)
        finishCleaning(report, into: current)
    }

    private func finishCleaning(_ report: RemovalReport, into outcome: CleanupOutcome) {
        let gone = Set((report.removed + report.alreadyGone).map(\.url.path))
        for category in results.keys {
            results[category]?.items.removeAll { gone.contains($0.id) }
        }
        selection.subtract(gone)
        self.outcome = outcome
        phase = .ready
    }
}
