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

    private let index: InstalledAppIndex
    private let makeFinder: @MainActor () -> OrphanFinder
    private let ignoreStore: OrphanIgnoreStore
    private let removal: RemovalService

    init(index: InstalledAppIndex = InstalledAppIndex(),
         makeFinder: @escaping @MainActor () -> OrphanFinder = { OrphanFinder(protected: ProtectedLocations.current()) },
         ignoreStore: OrphanIgnoreStore = OrphanIgnoreStore(),
         removal: RemovalService = RemovalService()) {
        self.index = index
        self.makeFinder = makeFinder
        self.ignoreStore = ignoreStore
        self.removal = removal
        ignored = ignoreStore.load()
    }

    @discardableResult
    func scan() -> Task<Void, Never>? {
        guard phase != .scanning, phase != .removing else { return nil }
        phase = .scanning
        let finder = makeFinder()
        let index = index
        let ignored = ignored
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return Task {
            let found = await Task.detached {
                // The installed list is loaded fresh every time: a stale list
                // would make a newly installed app's files look orphaned.
                try? finder.find(installed: index.apps(), runningBundleIDs: running, ignored: ignored)
            }.value
            self.items = found ?? []
            self.selection = []
            self.phase = .ready
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
        try? ignoreStore.save(ignored)
    }

    func stopIgnoring(_ path: String) {
        ignored.remove(path)
        try? ignoreStore.save(ignored)
    }

    // MARK: - Removal

    func trashSelection() async {
        let requests = selectedItems.map(\.removalRequest)
        guard !requests.isEmpty, phase == .ready else { return }
        phase = .removing
        let report = await removal.remove(requests)
        finish(report, into: CleanupOutcome(report))
    }

    func retryWithAdministrator() async {
        guard var current = outcome, !current.needsAdministrator.isEmpty, phase == .ready else { return }
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
