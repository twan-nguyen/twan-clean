import AppKit
import Combine

@MainActor
final class UninstallerViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case uninstalling
    }

    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isLoadingApps = false
    @Published private(set) var sizes: [String: Int64] = [:]
    @Published var searchText = ""
    @Published var sortBySize = false
    @Published private(set) var selectedApp: InstalledApp?
    @Published private(set) var leftovers: LeftoverScan?
    @Published private(set) var isFindingLeftovers = false
    @Published private(set) var leftoverError: String?
    @Published var selection: Set<String> = []
    @Published private(set) var phase: Phase = .idle
    @Published var outcome: CleanupOutcome?
    @Published var sensitivity: SearchSensitivity {
        didSet {
            UserDefaults.standard.set(sensitivity.rawValue, forKey: SearchSensitivity.defaultsKey)
            if oldValue != sensitivity { findLeftovers() }
        }
    }

    private let index: InstalledAppIndex
    private let makeFinder: @MainActor () -> LeftoverFinder
    private let removal: RemovalService
    private let sizeCache: AppSizeCache?
    private var findTask: Task<Void, Never>?
    private var hasLoaded = false

    init(index: InstalledAppIndex = InstalledAppIndex(),
         makeFinder: @escaping @MainActor () -> LeftoverFinder = { LeftoverFinder(protected: ProtectedLocations.current()) },
         removal: RemovalService = RemovalService(),
         sizeCache: AppSizeCache? = AppSizeCache()) {
        self.index = index
        self.makeFinder = makeFinder
        self.removal = removal
        self.sizeCache = sizeCache
        sensitivity = UserDefaults.standard.string(forKey: SearchSensitivity.defaultsKey)
            .flatMap(SearchSensitivity.init(rawValue:)) ?? .enhanced
    }

    // MARK: - Apps

    var visibleApps: [InstalledApp] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let filtered = query.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
        guard sortBySize else { return filtered }
        return filtered.sorted { (sizes[$0.id] ?? -1) > (sizes[$1.id] ?? -1) }
    }

    /// Loads the app list the first time the screen opens, never at launch,
    /// so a scan elsewhere is not slowed down by measuring every app.
    func loadAppsIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        reloadApps()
    }

    @discardableResult
    func reloadApps() -> Task<Void, Never> {
        isLoadingApps = true
        let index = index
        return Task {
            let found = await Task.detached { index.apps() }.value
            self.apps = found
            self.isLoadingApps = false
            if let selected = self.selectedApp, !found.contains(selected) { self.select(nil) }
            await self.measureSizes(of: found)
        }
    }

    private func measureSizes(of apps: [InstalledApp]) async {
        guard let sizeCache else { return }
        for app in apps where sizes[app.id] == nil {
            if Task.isCancelled { break }
            if let bytes = try? await sizeCache.size(of: app) { sizes[app.id] = bytes }
        }
        await sizeCache.save()
    }

    // MARK: - Selection and leftovers

    func select(_ app: InstalledApp?) {
        guard app != selectedApp, phase == .idle else { return }
        findTask?.cancel()
        selectedApp = app
        leftovers = nil
        leftoverError = nil
        selection = []
        isFindingLeftovers = false
        findLeftovers()
    }

    /// Opens an app handed over from Finder's Services menu. Returns false
    /// when it is not an app Twan Clean can uninstall.
    @discardableResult
    func selectApp(at url: URL) -> Bool {
        guard let app = InstalledAppIndex.app(at: url) else { return false }
        if !apps.contains(where: { $0.id == app.id }) {
            apps.append(app)
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        select(apps.first { $0.id == app.id })
        // The rest of the list still loads, as when the screen opens normally.
        loadAppsIfNeeded()
        return true
    }

    @discardableResult
    func findLeftovers() -> Task<Void, Never>? {
        findTask?.cancel()
        guard let app = selectedApp else { return nil }
        isFindingLeftovers = true
        let finder = makeFinder()
        let sensitivity = sensitivity
        let others = apps
        findTask = Task {
            let result = await Task.detached { () -> Result<LeftoverScan, Error> in
                Result { try finder.find(for: app, sensitivity: sensitivity, otherApps: others) }
            }.value
            guard !Task.isCancelled, self.selectedApp == app else { return }
            switch result {
            case .success(let scan):
                self.leftovers = scan
                self.selection = Set(scan.items.filter(\.selectedByDefault).map(\.id))
            case .failure(let error):
                self.leftovers = LeftoverScan()
                self.leftoverError = error.localizedDescription
            }
            self.isFindingLeftovers = false
        }
        return findTask
    }

    var selectedItems: [LeftoverItem] {
        (leftovers?.items ?? []).filter { selection.contains($0.id) }
    }

    var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.bytes }
    }

    func setSelected(_ item: LeftoverItem, _ selected: Bool) {
        if selected { selection.insert(item.id) } else { selection.remove(item.id) }
    }

    // MARK: - Uninstalling

    func isRunning(_ app: InstalledApp) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).isEmpty
    }

    /// Quits the app if it is running, unloads its launch agents and moves
    /// `items`, the selection the user confirmed, to the Trash. The list is
    /// locked meanwhile, so waiting for the app to quit cannot change what is
    /// removed.
    func uninstall(_ items: [LeftoverItem], of app: InstalledApp, forceQuit: Bool = false) async {
        guard !items.isEmpty, phase == .idle, app == selectedApp else { return }
        phase = .uninstalling
        defer { phase = .idle }

        if !(await quit(app, force: forceQuit)) {
            var outcome = CleanupOutcome(RemovalReport())
            outcome.failures.append(.init(name: app.name, message: String(localized: "The app is still running. Quit it and try again.")))
            self.outcome = outcome
            return
        }
        await unloadLaunchAgents(in: items)
        let report = await removal.remove(items.map(\.removalRequest))
        finish(report, into: CleanupOutcome(report))
    }

    func retryWithAdministrator(_ outcome: CleanupOutcome) async {
        guard !outcome.needsAdministrator.isEmpty, phase == .idle else { return }
        var current = outcome
        phase = .uninstalling
        defer { phase = .idle }
        let remover = PrivilegedRemover(
            service: removal,
            prompt: String(localized: "Twan Clean needs your password to remove the selected items."))
        let report = await remover.remove(current.needsAdministrator)
        current.add(report)
        finish(report, into: current)
    }

    private func finish(_ report: RemovalReport, into outcome: CleanupOutcome) {
        let gone = Set((report.removed + report.alreadyGone).map(\.url.path))
        leftovers?.items.removeAll { gone.contains($0.id) }
        selection.subtract(gone)
        if let app = selectedApp, gone.contains(app.url.path) {
            apps.removeAll { $0 == app }
            sizes[app.id] = nil
        }
        self.outcome = outcome
    }

    private func quit(_ app: InstalledApp, force: Bool) async -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier)
        guard !running.isEmpty else { return true }
        for app in running {
            if force { app.forceTerminate() } else { app.terminate() }
        }
        for _ in 0..<20 {
            if running.allSatisfy(\.isTerminated) { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return running.allSatisfy(\.isTerminated)
    }

    /// Stops the user's launch agents being removed, so nothing keeps running
    /// from the Trash. Only agents the removal policy accepts are touched;
    /// system-wide agents and daemons stop at the next restart.
    private func unloadLaunchAgents(in items: [LeftoverItem]) async {
        let agents = "\(removal.policy.rules.home)/Library/LaunchAgents"
        for item in items where item.url.pathExtension == "plist" && PathPolicy.isInside(item.url.path, agents)
            && removal.policy.evaluate(item.url, purpose: item.purpose) == .allowed(item.url) {
            _ = await ProcessRunner.run(URL(fileURLWithPath: "/bin/launchctl"),
                                        ["bootout", "gui/\(getuid())", item.url.path], timeout: 10)
        }
    }
}
