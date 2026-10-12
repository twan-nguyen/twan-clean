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
        guard app != selectedApp else { return }
        selectedApp = app
        leftovers = nil
        selection = []
        findLeftovers()
    }

    /// Opens an app handed over from Finder's Services menu.
    func selectApp(at url: URL) {
        hasLoaded = true
        if let known = apps.first(where: { PathPolicy.isSame($0.url.path, url.path) }) {
            select(known)
        } else if let app = InstalledAppIndex.app(at: url) {
            apps.append(app)
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            select(app)
        }
    }

    @discardableResult
    func findLeftovers() -> Task<Void, Never>? {
        findTask?.cancel()
        guard let app = selectedApp else { return nil }
        isFindingLeftovers = true
        let finder = makeFinder()
        let sensitivity = sensitivity
        findTask = Task {
            let scan = await Task.detached { try? finder.find(for: app, sensitivity: sensitivity) }.value
            guard !Task.isCancelled, self.selectedApp == app else { return }
            self.leftovers = scan ?? LeftoverScan()
            self.selection = Set((scan?.items ?? []).filter(\.selectedByDefault).map(\.id))
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

    /// Quits the app if it is running, unloads its launch agents and moves the
    /// selected items to the Trash.
    func uninstall(forceQuit: Bool = false) async {
        guard let app = selectedApp, !selectedItems.isEmpty, phase == .idle else { return }
        phase = .uninstalling
        defer { phase = .idle }

        if !(await quit(app, force: forceQuit)) {
            var outcome = CleanupOutcome(RemovalReport())
            outcome.failures.append(.init(name: app.name, message: String(localized: "The app is still running. Quit it and try again.")))
            self.outcome = outcome
            return
        }
        await unloadLaunchAgents(in: selectedItems)
        let report = await removal.remove(selectedItems.map(\.removalRequest))
        finish(report, into: CleanupOutcome(report))
    }

    func retryWithAdministrator() async {
        guard var current = outcome, !current.needsAdministrator.isEmpty, phase == .idle else { return }
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
    /// from the Trash. Agents that are not loaded are simply skipped.
    private func unloadLaunchAgents(in items: [LeftoverItem]) async {
        let agents = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents").path
        for item in items where item.url.pathExtension == "plist" && PathPolicy.isInside(item.url.path, agents) {
            _ = await ProcessRunner.run(URL(fileURLWithPath: "/bin/launchctl"),
                                        ["bootout", "gui/\(getuid())", item.url.path], timeout: 10)
        }
    }
}
