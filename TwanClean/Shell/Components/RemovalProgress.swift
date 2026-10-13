import Foundation

/// What a removal shows while it runs: the stage it is in and how many of its
/// items are settled. Each feature view model publishes one.
struct RemovalProgress: Equatable, Sendable {
    enum Stage: Equatable, Sendable {
        case stoppingServices
        case quittingApp(String)
        /// Deleting or moving what Smart Scan found.
        case cleaning
        case movingToTrash
        /// The macOS administrator prompt is open, or the command it approved
        /// is still running.
        case waitingForPassword
    }

    /// Tells one removal from the next, so a late update from a finished run
    /// can never show up on the next one.
    let run = UUID()
    var stage: Stage
    var completed = 0
    var total: Int
    var currentName: String?

    /// How far along, for the stages that count items; nil while the work has
    /// no measurable end.
    var fraction: Double? {
        switch stage {
        case .cleaning, .movingToTrash: total > 0 ? Double(completed) / Double(total) : nil
        case .stoppingServices, .quittingApp, .waitingForPassword: nil
        }
    }
}

/// Lets a removal that can touch thousands of items update the interface a
/// few times a second instead of once per item. Small runs pass every step,
/// and the last step of a run always passes.
final class ProgressThrottle: @unchecked Sendable {
    private let interval: TimeInterval
    private let everyStepUpTo: Int
    private let clock: @Sendable () -> TimeInterval
    private let lock = NSLock()
    private var lastPassed: TimeInterval?

    init(interval: TimeInterval = 0.05, everyStepUpTo: Int = 20,
         clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.interval = interval
        self.everyStepUpTo = everyStepUpTo
        self.clock = clock
    }

    func passes(_ step: RemovalStep) -> Bool {
        if step.total <= everyStepUpTo || step.completed >= step.total { return true }
        lock.lock()
        defer { lock.unlock() }
        let now = clock()
        if let lastPassed, now - lastPassed < interval { return false }
        lastPassed = now
        return true
    }
}

/// A view model that shows its removal's progress.
@MainActor
protocol RemovalProgressPublishing: AnyObject, Sendable {
    var removalProgress: RemovalProgress? { get set }
}

extension RemovalProgressPublishing {
    /// Starts showing a removal and returns the handler to give the removal
    /// service. Pair it with `endRemoval()`, typically in a `defer`.
    func beginRemoval(_ stage: RemovalProgress.Stage, total: Int) -> RemovalProgressHandler {
        let started = RemovalProgress(stage: stage, total: total)
        removalProgress = started
        let run = started.run
        let throttle = ProgressThrottle()
        return { [weak self] step in
            guard throttle.passes(step) else { return }
            Task { @MainActor in self?.apply(step, run: run) }
        }
    }

    /// Moves the removal on to its next stage, keeping the count.
    func setRemovalStage(_ stage: RemovalProgress.Stage) {
        removalProgress?.stage = stage
    }

    func endRemoval() {
        removalProgress = nil
    }

    private func apply(_ step: RemovalStep, run: UUID) {
        guard var current = removalProgress, current.run == run, step.completed >= current.completed else { return }
        current.completed = step.completed
        current.total = step.total
        current.currentName = step.url.lastPathComponent
        removalProgress = current
    }
}
