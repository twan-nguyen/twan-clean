import AppKit
import Combine

@MainActor
final class UninstallerViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case uninstalling
    }

    /// How an app handed over from Finder's Services menu was received.
    enum ServiceResult: Equatable {
        case selected
        case rejected(FinderServiceRejection)
    }

    /// How long to wait for an app to quit, and for a helper that launchd
    /// starts again to show up.
    struct QuitTiming: Sendable {
        var pollInterval: UInt64 = 250_000_000
        var polls = 20
        var settle: UInt64 = 1_000_000_000
        var respawnRounds = 3

        static let standard = QuitTiming()
        static let immediate = QuitTiming(pollInterval: 0, polls: 1, settle: 0, respawnRounds: 3)
    }

    typealias LaunchControl = @Sendable ([String]) async -> ProcessResult?

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
            defaults.set(sensitivity.rawValue, forKey: SearchSensitivity.defaultsKey)
            if oldValue != sensitivity { findLeftovers() }
        }
    }

    private let index: InstalledAppIndex
    private let makeFinder: @MainActor () -> LeftoverFinder
    private let removal: RemovalService
    private let sizeCache: AppSizeCache?
    private let processes: any AppProcessControl
    private let launchctl: LaunchControl
    private let timing: QuitTiming
    private let defaults: UserDefaults
    /// Installed apps that cannot be uninstalled from here, but whose files
    /// are not another app's to take.
    private var relatedApps: [InstalledApp] = []
    private(set) var findTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false

    init(index: InstalledAppIndex = .standard,
         makeFinder: @escaping @MainActor () -> LeftoverFinder = { LeftoverFinder(protected: ProtectedLocations.current()) },
         removal: RemovalService = RemovalService(),
         sizeCache: AppSizeCache? = AppSizeCache(),
         processes: any AppProcessControl = SystemAppProcessControl(),
         launchctl: @escaping LaunchControl = { arguments in
             await ProcessRunner.run(URL(fileURLWithPath: "/bin/launchctl"), arguments, timeout: 10)
         },
         timing: QuitTiming = .standard,
         defaults: UserDefaults = .standard) {
        self.index = index
        self.makeFinder = makeFinder
        self.removal = removal
        self.sizeCache = sizeCache
        self.processes = processes
        self.launchctl = launchctl
        self.timing = timing
        self.defaults = defaults
        sensitivity = defaults.string(forKey: SearchSensitivity.defaultsKey)
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

    /// The returned task also covers measuring the apps' sizes.
    @discardableResult
    func reloadApps() -> Task<Void, Never> {
        isLoadingApps = true
        let index = index
        let load = Task {
            let catalog = await runDetached { index.catalog() }
            self.apply(catalog)
        }
        loadTask = load
        return Task {
            await load.value
            await self.measureSizes(of: self.apps)
        }
    }

    /// Waits for the app list, loading it first if nothing has yet. A scan
    /// for leftovers needs every installed app, or it could not tell whose
    /// file is whose.
    func waitForAppList() async {
        loadAppsIfNeeded()
        await loadTask?.value
    }

    private func apply(_ catalog: AppCatalog) {
        apps = catalog.listed
        relatedApps = catalog.related
        isLoadingApps = false
        guard let selected = selectedApp, !catalog.listed.contains(where: { $0.id == selected.id }) else { return }
        // An app opened from Finder may sit deeper than the list looks; it
        // stays unless it is gone.
        if let current = InstalledAppIndex.app(at: selected.url) {
            apps.append(current)
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } else {
            select(nil)
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

    /// Opens an app handed over from Finder's Services menu, or says why it
    /// cannot be uninstalled.
    @discardableResult
    func selectApp(at url: URL, policy: PathPolicy = PathPolicy()) -> ServiceResult {
        switch FinderServiceRequest.validate(url, policy: policy) {
        case .failure(let rejection):
            return .rejected(rejection)
        case .success(let app):
            return open(app)
        }
    }

    /// Opens the first of `urls` that can be uninstalled.
    @discardableResult
    func selectApp(from urls: [URL], policy: PathPolicy = PathPolicy()) -> ServiceResult {
        switch FinderServiceRequest.app(from: urls, policy: policy) {
        case .failure(let rejection):
            return .rejected(rejection)
        case .success(let app):
            return open(app)
        }
    }

    private func open(_ app: InstalledApp) -> ServiceResult {
        // Switching apps while one is being removed would change what the
        // confirmed removal covers.
        guard phase == .idle else { return .rejected(.busy) }
        if !apps.contains(where: { $0.id == app.id }) {
            apps.append(app)
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        // The rest of the list loads as when the screen opens normally; the
        // scan below waits for it.
        loadAppsIfNeeded()
        select(apps.first { $0.id == app.id })
        return .selected
    }

    @discardableResult
    func findLeftovers() -> Task<Void, Never>? {
        findTask?.cancel()
        guard let app = selectedApp else { return nil }
        isFindingLeftovers = true
        let finder = makeFinder()
        let sensitivity = sensitivity
        let task = Task {
            await self.waitForAppList()
            guard !Task.isCancelled, self.selectedApp == app else { return }
            // Copies of the app with another identifier are not rivals of the
            // app, but a related one with the same identifier is not a copy
            // that stays either.
            let others = self.apps + self.relatedApps.filter {
                $0.bundleIdentifier.caseInsensitiveCompare(app.bundleIdentifier) != .orderedSame
            }
            let result = await runDetached { () -> Result<LeftoverScan, Error> in
                Result { try finder.find(for: app, sensitivity: sensitivity, otherApps: others) }
            }
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
        findTask = task
        return task
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
        !processes.running(for: app, matchingIdentifier: !hasAnotherCopy(of: app)).isEmpty
    }

    /// Whether the app is installed a second time, which the identifier alone
    /// cannot tell apart from the first.
    private func hasAnotherCopy(of app: InstalledApp) -> Bool {
        apps.contains { $0.bundleIdentifier.caseInsensitiveCompare(app.bundleIdentifier) == .orderedSame && $0.url.path != app.url.path }
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
        // The app's own agents go with the app; kept, they keep running.
        if items.contains(where: { $0.purpose == .appBundle }) { await stopBundledAgents(of: app) }
        let stillRunning = await quit(app, force: forceQuit)
        guard stillRunning.isEmpty else {
            var outcome = CleanupOutcome(RemovalReport())
            let names = ListFormatter.localizedString(byJoining: stillRunning.sorted())
            outcome.failures.append(.init(name: app.name, message: String(
                localized: "Still running: \(names). Try Force Quit and Uninstall.")))
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
    /// names of those that did not. A helper that launchd starts again after
    /// being quit is found by looking again once things have settled, and
    /// quit in its turn.
    private func quit(_ app: InstalledApp, force: Bool) async -> [String] {
        let byIdentifier = !hasAnotherCopy(of: app)
        for round in 0...timing.respawnRounds {
            let running = processes.running(for: app, matchingIdentifier: byIdentifier)
            if running.isEmpty { return [] }
            // Out of patience: something keeps coming back.
            if round == timing.respawnRounds { return running.map(\.name) }

            for process in running { processes.terminate(process, force: force) }
            for _ in 0..<timing.polls {
                if running.allSatisfy(processes.hasExited) { break }
                try? await Task.sleep(nanoseconds: timing.pollInterval)
            }
            let stuck = running.filter { !processes.hasExited($0) }
            if !stuck.isEmpty { return stuck.map(\.name) }
            try? await Task.sleep(nanoseconds: timing.settle)
        }
        return []
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
            _ = await launchctl(["bootout", "gui/\(getuid())", item.url.path])
        }
    }

    /// Stops the login-item agents the app registers from inside its own
    /// bundle (`Contents/Library/LaunchAgents`), which belong to the user's
    /// session and are not in any Library folder. Daemons registered the same
    /// way run as root; stopping those needs the administrator prompt, which
    /// only `PrivilegedRemover` may show, and it knows daemons solely by their
    /// plist in /Library/LaunchDaemons.
    private func stopBundledAgents(of app: InstalledApp) async {
        // Still the bundle the scan found, not one swapped in since.
        guard FileIdentity.lookup(app.url) == .found(app.identity) else { return }
        let folder = app.url.appendingPathComponent("Contents/Library/LaunchAgents")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names.sorted() where name.hasSuffix(".plist") {
            guard let label = NestedBundles.label(ofPlistAt: folder.appendingPathComponent(name)),
                  Self.isStoppable(label: label) else { continue }
            _ = await launchctl(["bootout", "gui/\(getuid())/\(label)"])
        }
    }

    /// An app's own agent, not one of macOS's that its bundle merely names.
    nonisolated static func isStoppable(label: String) -> Bool {
        !label.isEmpty && !label.hasPrefix("com.apple.") && !label.contains("/")
            && label.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }
}
