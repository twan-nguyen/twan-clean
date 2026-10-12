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
        !runningProcesses(of: app).isEmpty
    }

    private struct RunningProcess {
        let pid: pid_t
        let name: String
        /// Set for processes that are apps, which are asked to quit politely.
        let application: NSRunningApplication?

        var isTerminated: Bool { application?.isTerminated ?? !ProcessList.isRunning(pid) }
    }

    /// Whether a process is part of `app`: the app itself, wherever it runs
    /// from, or a helper started from inside its bundle, such as a login item,
    /// a menu bar agent or a plain executable, which keeps running after the
    /// app quits.
    nonisolated static func belongs(bundleIdentifier: String?, path: String?, to appIdentifier: String, at appPath: String) -> Bool {
        if let bundleIdentifier, bundleIdentifier == appIdentifier { return true }
        guard let path else { return false }
        return PathPolicy.isSame(path, appPath) || PathPolicy.isInside(path, appPath)
    }

    private func runningProcesses(of app: InstalledApp) -> [RunningProcess] {
        let ownPID = getpid()
        var found: [pid_t: RunningProcess] = [:]
        for process in NSWorkspace.shared.runningApplications where process.processIdentifier != ownPID {
            let path = (process.bundleURL ?? process.executableURL)?.path
            if Self.belongs(bundleIdentifier: process.bundleIdentifier, path: path,
                            to: app.bundleIdentifier, at: app.url.path) {
                found[process.processIdentifier] = RunningProcess(
                    pid: process.processIdentifier, name: process.localizedName ?? app.name, application: process)
            }
        }
        // Only processes this user may stop: a root helper inside the bundle
        // would otherwise block the uninstall for good.
        for (pid, path) in ProcessList.executablePaths()
        where pid != ownPID && found[pid] == nil && ProcessList.canSignal(pid)
            && Self.belongs(bundleIdentifier: nil, path: path, to: app.bundleIdentifier, at: app.url.path) {
            found[pid] = RunningProcess(pid: pid, name: (path as NSString).lastPathComponent, application: nil)
        }
        return Array(found.values)
    }

    /// Unloads the app's launch agents, quits the app and its helpers, and
    /// moves `items`, the selection the user confirmed, to the Trash. Agents
    /// go first: launchd would otherwise start a quit helper again. The list is
    /// locked meanwhile, so waiting for the app to quit cannot change what is
    /// removed.
    func uninstall(_ items: [LeftoverItem], of app: InstalledApp, forceQuit: Bool = false) async {
        guard !items.isEmpty, phase == .idle, app == selectedApp else { return }
        phase = .uninstalling
        defer { phase = .idle }

        await unloadLaunchAgents(in: items)
        let stillRunning = await quit(app, force: forceQuit)
        guard stillRunning.isEmpty else {
            var outcome = CleanupOutcome(RemovalReport())
            let names = ListFormatter.localizedString(byJoining: stillRunning.sorted())
            outcome.failures.append(.init(name: app.name, message: String(
                localized: "Still running: \(names). Quit them, or uninstall again and choose Force Quit and Uninstall.")))
            self.outcome = outcome
            return
        }
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

    /// Asks the app and its helpers to quit, or forces them, and returns the
    /// names of those still running after a few seconds.
    private func quit(_ app: InstalledApp, force: Bool) async -> [String] {
        let running = runningProcesses(of: app)
        for process in running {
            if let application = process.application {
                if force { application.forceTerminate() } else { application.terminate() }
            } else {
                kill(process.pid, force ? SIGKILL : SIGTERM)
            }
        }
        for _ in 0..<20 {
            if running.allSatisfy(\.isTerminated) { break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return running.filter { !$0.isTerminated }.map(\.name)
    }

    /// Stops the launch agents being removed, so nothing keeps running from
    /// the Trash. Agents in the user's and the shared Library run in the
    /// user's session and can be stopped without a password; system daemons
    /// are stopped by `PrivilegedRemover` before their plists are trashed.
    private func unloadLaunchAgents(in items: [LeftoverItem]) async {
        let folders = ["\(removal.policy.rules.home)/Library/LaunchAgents", "/Library/LaunchAgents"]
        for item in items where item.url.pathExtension == "plist"
            && folders.contains(where: { PathPolicy.isInside(item.url.path, $0) })
            && removal.policy.evaluate(item.url, purpose: item.purpose) == .allowed(item.url)
            // Still the file the scan found, not one swapped in since.
            && FileIdentity.lookup(item.url) == .found(item.identity) {
            _ = await ProcessRunner.run(URL(fileURLWithPath: "/bin/launchctl"),
                                        ["bootout", "gui/\(getuid())", item.url.path], timeout: 10)
        }
    }
}
