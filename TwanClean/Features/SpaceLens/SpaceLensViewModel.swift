import AppKit
import Combine

@MainActor
final class SpaceLensViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning
        case ready
        case removing
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var root: SizeNode?
    /// The folders from the root down to the one on screen.
    @Published private(set) var path: [SizeNode] = []
    @Published private(set) var selection: [SizeNode] = []
    @Published private(set) var scanStarted: Date?
    @Published var outcome: CleanupOutcome?
    /// Bumped when the tree changes in place, so views redraw.
    @Published private(set) var revision = 0

    let progress = ScanProgressReporter()
    private let builder: SizeTreeBuilder
    private let removal: RemovalService
    private let home: URL
    private var scanTask: Task<Void, Never>?
    /// Whether the scanned folder came from an Open panel.
    private var rootWasChosen = false

    private let protectedLocations: @MainActor (URL?) -> ProtectedLocations?

    init(builder: SizeTreeBuilder = SizeTreeBuilder(), removal: RemovalService = RemovalService(),
         home: URL = FileManager.default.homeDirectoryForCurrentUser,
         protectedLocations: @escaping @MainActor (URL?) -> ProtectedLocations? = { ProtectedLocations.current(consentedFolder: $0) }) {
        self.builder = builder
        self.removal = removal
        self.home = home
        self.protectedLocations = protectedLocations
    }

    var current: SizeNode? { path.last }

    // MARK: - Scanning

    @discardableResult
    func scanHome() -> Task<Void, Never>? {
        scan(home)
    }

    /// Scans a folder. `chosenByUser` means it came from an Open panel, which
    /// macOS counts as permission to read it.
    @discardableResult
    func scan(_ folder: URL, chosenByUser: Bool = false) -> Task<Void, Never>? {
        guard phase != .scanning, phase != .removing else { return nil }
        phase = .scanning
        scanStarted = Date()
        selection = []
        rootWasChosen = chosenByUser
        let protected = protectedLocations(chosenByUser ? folder : nil)
        scanTask = Task { [builder, progress] in
            do {
                let tree = try await builder.build(folder, progress: progress, protected: protected)
                self.root = tree
                self.path = [tree]
                self.phase = .ready
            } catch {
                self.phase = self.root == nil ? .idle : .ready
            }
        }
        return scanTask
    }

    @discardableResult
    func rescan() -> Task<Void, Never>? {
        guard let root else { return nil }
        return scan(root.url, chosenByUser: rootWasChosen)
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    // MARK: - Navigation

    func open(_ node: SizeNode) {
        guard node.isFolder, !node.children.isEmpty else { return }
        path.append(node)
    }

    func goBack(to node: SizeNode) {
        guard let index = path.firstIndex(where: { $0 === node }) else { return }
        path.removeSubrange((index + 1)...)
    }

    func goUp() {
        if path.count > 1 { path.removeLast() }
    }

    // MARK: - Selection

    func isSelected(_ node: SizeNode) -> Bool {
        selection.contains { $0 === node }
    }

    func toggle(_ node: SizeNode) {
        if let index = selection.firstIndex(where: { $0 === node }) {
            selection.remove(at: index)
        } else {
            // A folder and something inside it would be counted twice.
            selection.removeAll { selected in
                selected.ancestors.contains { $0 === node } || node.ancestors.contains { $0 === selected }
            }
            selection.append(node)
        }
    }

    var selectedBytes: Int64 {
        selection.reduce(0) { $0 + $1.bytes }
    }

    // MARK: - Removal

    /// Space Lens only ever moves items to the Trash. The purpose follows
    /// where the item is, and the policy refuses anything outside those areas.
    func purpose(for url: URL) -> RemovalPurpose {
        let path = url.path
        let homePath = removal.policy.rules.home
        if url.pathExtension.lowercased() == "app",
           ["/Applications", "\(homePath)/Applications"].contains(where: { PathPolicy.isInside(path, $0) }) {
            return .appBundle
        }
        if PathPolicy.isInside(path, "\(homePath)/Library/Developer/Xcode/Archives") {
            return .buildArchive
        }
        if PathPolicy.isInside(path, "\(homePath)/Library") {
            return .appLeftover
        }
        return .userFile
    }

    func trashSelection() async {
        let nodes = selection.filter { $0.identity != nil }
        guard !nodes.isEmpty, phase == .ready else { return }
        phase = .removing
        let requests = nodes.map { node in
            RemovalRequest(url: node.url, purpose: purpose(for: node.url), identity: node.identity!, bytes: node.bytes)
        }
        let report = await removal.remove(requests)
        let gone = Set((report.removed + report.alreadyGone).map(\.url.path))
        for node in nodes where gone.contains(node.url.path) {
            node.parent?.remove(node)
        }
        selection.removeAll { gone.contains($0.url.path) || $0.parent == nil }
        outcome = CleanupOutcome(report)
        revision += 1
        phase = .ready
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
        let gone = Set(report.removed.map(\.url.path))
        for node in selection where gone.contains(node.url.path) {
            node.parent?.remove(node)
        }
        selection.removeAll { gone.contains($0.url.path) }
        current.add(report)
        self.outcome = current
        revision += 1
        phase = .ready
    }
}
