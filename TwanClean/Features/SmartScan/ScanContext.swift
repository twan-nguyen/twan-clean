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
    /// Bundle identifiers of running apps, lowercased.
    let runningBundleIDs: Set<String>
    let progress: ScanProgressReporter
    let now: Date

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         policy: PathPolicy? = nil,
         sizing: AllocatedSizeCalculator = AllocatedSizeCalculator(),
         commands: CommandRunner? = nil,
         settings: ScanSettings = ScanSettings(),
         runningBundleIDs: Set<String> = [],
         progress: ScanProgressReporter = ScanProgressReporter(),
         now: Date = Date()) {
        self.home = home
        self.policy = policy ?? PathPolicy(rules: SafetyRules(homeDirectory: home))
        self.sizing = sizing
        self.commands = commands ?? CommandRunner(home: home)
        self.settings = settings
        self.runningBundleIDs = Set(runningBundleIDs.map { $0.lowercased() })
        self.progress = progress
        self.now = now
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

    /// Adds every entry directly inside `folder`.
    mutating func addChildren(of folder: URL, purpose: RemovalPurpose, selected: Bool = true,
                              notes: Set<CleanableItem.Note> = [],
                              where include: (URL) -> Bool = { _ in true }) throws {
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
                try add(url, purpose: purpose, selected: selected, notes: notes)
            }
        }
    }

    /// Adds one item when the policy allows it and it takes up space.
    mutating func add(_ url: URL, purpose: RemovalPurpose, selected: Bool = true,
                      notes: Set<CleanableItem.Note> = []) throws {
        try Task.checkCancellation()
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
        if belongsToRunningApp(canonical) { notes.insert(.appIsRunning) }
        if canonical.lastPathComponent.lowercased().hasPrefix("com.apple.") { notes.insert(.usedByMacOS) }
        let needsAdministrator = Self.needsAdministrator(canonical)
        // Only the user's own regenerable junk is ever preselected: nothing
        // outside the home folder, nothing behind a password, nothing a
        // running app or macOS itself is using, and no personal data.
        let preselect = selected
            && !needsAdministrator
            && PathPolicy.isInside(canonical.path, context.policy.rules.home)
            && notes.isDisjoint(with: [.appIsRunning, .personalData, .mayBeNeeded, .usedByMacOS])

        result.items.append(CleanableItem(
            url: canonical, category: result.category, identity: identity,
            isDirectory: Self.isDirectory(canonical), bytes: size.bytes,
            purpose: purpose, requiresAdministrator: needsAdministrator, selectedByDefault: preselect,
            lastModified: size.latestModification, notes: notes))
    }

    mutating func noteUnreadable(_ url: URL) {
        result.unreadableLocations.append(url)
    }

    mutating func setDockerReclaimable(_ bytes: Int64?) {
        result.dockerReclaimableBytes = bytes
    }

    func finish() -> CategoryResult {
        var result = result
        result.items.sort { $0.bytes > $1.bytes }
        return result
    }

    /// Whether removing the item will need the administrator prompt: its
    /// folder is not writable, a sticky folder (like /tmp) protects another
    /// user's item, or a folder owned by someone else will have contents this
    /// user cannot remove.
    static func needsAdministrator(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent().path
        guard access(parent, W_OK) == 0 else { return true }
        var parentStatus = stat()
        var itemStatus = stat()
        guard lstat(parent, &parentStatus) == 0, lstat(url.path, &itemStatus) == 0 else { return true }
        let ownedByOther = itemStatus.st_uid != getuid()
        let isDirectory = (itemStatus.st_mode & S_IFMT) == S_IFDIR
        let parentIsSticky = (parentStatus.st_mode & S_ISVTX) != 0
        return ownedByOther && (parentIsSticky || isDirectory)
    }

    static func isDirectory(_ url: URL) -> Bool {
        var status = stat()
        return lstat(url.path, &status) == 0 && (status.st_mode & S_IFMT) == S_IFDIR
    }

    /// Cache folders are usually named after the app's bundle identifier.
    private func belongsToRunningApp(_ url: URL) -> Bool {
        var name = url.lastPathComponent.lowercased()
        for suffix in [".savedstate", ".binarycookies"] where name.hasSuffix(suffix) {
            name.removeLast(suffix.count)
        }
        return context.runningBundleIDs.contains(name)
    }

    static let ignoredNames: Set<String> = [".DS_Store", ".localized", ".com.apple.timemachine.supported"]
}
