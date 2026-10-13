import Foundation

/// Shares the path being scanned with the interface without a main-thread hop
/// per file; the interface samples it a few times a second.
final class ScanProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var path: String?

    func report(_ url: URL) {
        lock.lock()
        path = url.path
        lock.unlock()
    }

    var currentPath: String? {
        lock.lock()
        defer { lock.unlock() }
        return path
    }
}

/// Everything a category scanner needs, so scanners stay free of globals and
/// can be tested against a fake home folder.
struct ScanContext: Sendable {
    let home: URL
    let policy: PathPolicy
    let sizing: AllocatedSizeCalculator
    let commands: CommandRunner
    let settings: ScanSettings
    /// The apps running now, matched against cache folder names.
    let running: RunningAppIndex
    let progress: ScanProgressReporter
    let now: Date
    /// Locations to leave unread so macOS does not prompt; nil once Full
    /// Disk Access is granted.
    let protectedLocations: ProtectedLocations?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         policy: PathPolicy? = nil,
         sizing: AllocatedSizeCalculator = AllocatedSizeCalculator(),
         commands: CommandRunner? = nil,
         settings: ScanSettings = ScanSettings(),
         runningBundleIDs: Set<String> = [],
         runningApps: [RunningApp] = [],
         progress: ScanProgressReporter = ScanProgressReporter(),
         now: Date = Date(),
         protectedLocations: ProtectedLocations? = nil) {
        self.home = home
        self.policy = policy ?? PathPolicy(rules: SafetyRules(homeDirectory: home))
        self.sizing = sizing
        self.commands = commands ?? CommandRunner(home: home)
        self.settings = settings
        self.running = RunningAppIndex(bundleIDs: runningBundleIDs, apps: runningApps)
        self.progress = progress
        self.now = now
        self.protectedLocations = protectedLocations
    }

    /// Whether reading `url` could make macOS ask for permission.
    func isProtected(_ url: URL) -> Bool {
        protectedLocations?.contains(url) ?? false
    }

    func homeURL(_ relative: String) -> URL {
        home.appendingPathComponent(relative)
    }
}

/// Collects the items of one category, applying the rules every scanner
/// shares: only paths the policy allows, sizes from the shared sizing
/// session, and nothing preselected that needs a password or belongs to a
/// running app.
struct CategoryResultBuilder {
    let context: ScanContext
    private(set) var result: CategoryResult

    init(_ category: CleanupCategoryID, context: ScanContext) {
        self.context = context
        result = CategoryResult(category: category, items: [])
    }

    /// Adds every entry directly inside `folder`. `owners` names apps (bundle
    /// identifier, app name or vendor) that use the entries without the
    /// entries being named after them.
    mutating func addChildren(of folder: URL, purpose: RemovalPurpose, selected: Bool = true,
                              notes: Set<CleanableItem.Note> = [], owners: Set<String> = [],
                              where include: (URL) -> Bool = { _ in true }) throws {
        guard !context.isProtected(folder) else {
            noteLocked(folder)
            return
        }
        let entries: [String]
        do {
            entries = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        } catch CocoaError.fileReadNoSuchFile {
            return
        } catch {
            if FileManager.default.fileExists(atPath: folder.path) {
                result.unreadableLocations.append(folder)
            }
            return
        }
        for entry in entries.sorted() where !Self.ignoredNames.contains(entry) {
            let url = folder.appendingPathComponent(entry)
            if include(url) {
                try add(url, purpose: purpose, selected: selected, notes: notes, owners: owners)
            }
        }
    }

    /// Adds one item when the policy allows it and it takes up space.
    mutating func add(_ url: URL, purpose: RemovalPurpose, selected: Bool = true,
                      notes: Set<CleanableItem.Note> = [], owners: Set<String> = []) throws {
        try Task.checkCancellation()
        guard !context.isProtected(url) else {
            noteLocked(url)
            return
        }
        guard case .allowed(let canonical) = context.policy.evaluate(url, purpose: purpose),
              let identity = FileIdentity.of(canonical),
              !result.items.contains(where: { $0.url == canonical }) else { return }

        context.progress.report(canonical)
        let size: SizeMeasurement
        do {
            size = try context.sizing.measure(canonical)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            result.unreadableLocations.append(canonical)
            return
        }
        guard size.bytes > 0 else { return }

        var notes = notes
        if size.unreadableEntries > 0 { notes.insert(.partlyUnreadable) }
        let name = canonical.lastPathComponent.lowercased()
        // Xcode's own caches are not macOS's: they are rebuilt by Xcode alone,
        // and are in use only while Xcode runs.
        let isXcodeCache = name.hasPrefix(Self.xcodeCachePrefix)
        var owners = owners
        if isXcodeCache { owners.insert("com.apple.dt.xcode") }
        if context.running.owns(folderNamed: canonical.lastPathComponent, owners: owners) { notes.insert(.appIsRunning) }
        if name.hasPrefix("com.apple.") && !isXcodeCache { notes.insert(.usedByMacOS) }
        let needsAdministrator = RemovalService.needsAdministrator(canonical)
        // Only the user's own regenerable junk is ever preselected: nothing
        // outside the home folder, nothing behind a password, nothing a
        // running app or macOS itself is using, and no personal data.
        let preselect = selected
            && !needsAdministrator
            && PathPolicy.isInside(canonical.path, context.policy.rules.home)
            && notes.isDisjoint(with: [.appIsRunning, .personalData, .mayBeNeeded, .usedByMacOS])

        result.items.append(CleanableItem(
            url: canonical, category: result.category, identity: identity,
            isDirectory: Self.isDirectory(canonical), bytes: size.reclaimableBytes,
            purpose: purpose, requiresAdministrator: needsAdministrator, selectedByDefault: preselect,
            lastModified: size.latestModification, notes: notes))
    }

    mutating func noteUnreadable(_ url: URL) {
        result.unreadableLocations.append(url)
    }

    /// A protected location skipped without reading it, when it exists.
    private mutating func noteLocked(_ url: URL) {
        if FileIdentity.of(url) != nil, !result.unreadableLocations.contains(url) {
            result.unreadableLocations.append(url)
        }
    }

    mutating func setDockerReclaimable(_ bytes: Int64?) {
        result.dockerReclaimableBytes = bytes
    }

    func finish() -> CategoryResult {
        var result = result
        result.items.sort { $0.bytes > $1.bytes }
        return result
    }

    static func isDirectory(_ url: URL) -> Bool {
        var status = stat()
        return lstat(url.path, &status) == 0 && (status.st_mode & S_IFMT) == S_IFDIR
    }

    private static let xcodeCachePrefix = "com.apple.dt.xcode"

    static let ignoredNames: Set<String> = [".DS_Store", ".localized", ".com.apple.timemachine.supported"]
}
