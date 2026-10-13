import AppKit
import Combine

@MainActor
final class OrphansViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning
        case ready
        case removing
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var items: [OrphanItem] = []
    @Published var selection: Set<String> = []
    @Published private(set) var ignored: Set<String>
    @Published var outcome: CleanupOutcome?
    /// Why the last scan could not tell what is left over. Shown instead of
    /// an empty result, which would claim there is nothing.
    @Published private(set) var scanError: String?
    /// A problem with the ignore list that the user should know about.
    @Published private(set) var notice: String?

    private let index: InstalledAppIndex
    private let makeFinder: @MainActor () -> OrphanFinder
    private let ignoreStore: OrphanIgnoreStore
    private let removal: RemovalService
    private let runningBundleIDs: @MainActor () -> Set<String>

    init(index: InstalledAppIndex = .everything,
         makeFinder: @escaping @MainActor () -> OrphanFinder = { OrphanFinder(protected: ProtectedLocations.current()) },
         ignoreStore: OrphanIgnoreStore = OrphanIgnoreStore(),
         removal: RemovalService = RemovalService(),
         runningBundleIDs: @escaping @MainActor () -> Set<String> = {
             Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
         }) {
        self.index = index
        self.makeFinder = makeFinder
        self.ignoreStore = ignoreStore
        self.removal = removal
        self.runningBundleIDs = runningBundleIDs
        let loaded = ignoreStore.loadReportingDamage()
        ignored = loaded.paths
        if loaded.wasUnreadable {
            notice = loaded.backup.map {
                String(localized: "The ignore list could not be read, so it was reset. The old file was kept as \($0.lastPathComponent).")
            } ?? String(localized: "The ignore list could not be read, so it was reset.")
        }
    }

    @discardableResult
    func scan() -> Task<Void, Never>? {
        guard phase != .scanning, phase != .removing else { return nil }
        phase = .scanning
        scanError = nil
        let finder = makeFinder()
        let index = index
        let ignored = ignored
        let running = runningBundleIDs()
        return Task {
            // The installed list is loaded fresh every time: a stale list
            // would make a newly installed app's files look orphaned.
            let result = await runDetached { () -> Result<[OrphanItem], Error> in
                Result {
                    let catalog = index.catalog()
                    guard catalog.isComplete else { throw OrphanFinder.ScanError.incompleteAppList }
                    return try finder.find(installed: catalog.everyApp, runningBundleIDs: running, ignored: ignored,
                                           extraIdentifiers: catalog.extraIdentifiers)
                }
            }
            self.selection = []
            switch result {
            case .success(let found):
                self.items = found
                self.phase = .ready
            case .failure(let error) where error is CancellationError:
                self.phase = .idle
            case .failure(let error):
                self.items = []
                self.scanError = error.localizedDescription
                self.phase = .ready
            }
        }
    }

    var groups: [(location: URL, items: [OrphanItem])] {
        Dictionary(grouping: items, by: \.location)
            .map { ($0.key, $0.value) }
            .sorted { $0.items.reduce(0) { $0 + $1.bytes } > $1.items.reduce(0) { $0 + $1.bytes } }
    }

    var selectedItems: [OrphanItem] { items.filter { selection.contains($0.id) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }

    func setSelected(_ item: OrphanItem, _ selected: Bool) {
        if selected { selection.insert(item.id) } else { selection.remove(item.id) }
    }

    // MARK: - Ignoring

    func ignore(_ item: OrphanItem) {
        ignored.insert(item.id)
        items.removeAll { $0.id == item.id }
        selection.remove(item.id)
        saveIgnored()
    }

    func stopIgnoring(_ path: String) {
        ignored.remove(path)
        saveIgnored()
    }

    func dismissNotice() {
        notice = nil
    }

    private func saveIgnored() {
        do {
            try ignoreStore.save(ignored)
        } catch {
            notice = String(localized: "The ignore list could not be saved: \(error.localizedDescription)")
        }
    }

    // MARK: - Removal

    func trashSelection() async {
        let requests = selectedItems.map(\.removalRequest)
        guard !requests.isEmpty, phase == .ready else { return }
        phase = .removing
        let report = await removal.remove(requests)
        finish(report, into: CleanupOutcome(report))
    }

    /// Retries what permissions blocked, after the administrator prompt. The
    /// outcome is passed in because its sheet is already closed by then.
    func retryWithAdministrator(_ outcome: CleanupOutcome) async {
        guard !outcome.needsAdministrator.isEmpty, phase == .ready else { return }
        var current = outcome
        phase = .removing
        let remover = PrivilegedRemover(
            service: removal,
            prompt: String(localized: "Twan Clean needs your password to remove the selected items."))
        let report = await remover.remove(current.needsAdministrator)
        current.add(report)
        finish(report, into: current)
    }

    private func finish(_ report: RemovalReport, into outcome: CleanupOutcome) {
        let gone = Set((report.removed + report.alreadyGone).map(\.url.path))
        items.removeAll { gone.contains($0.id) }
        selection.subtract(gone)
        self.outcome = outcome
        phase = .ready
    }
}
