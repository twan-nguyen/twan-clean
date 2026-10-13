import Combine
import Foundation
@testable import TwanClean

/// Collects the steps a removal reports, from whichever thread reports them.
final class StepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [RemovalStep] = []

    var steps: [RemovalStep] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var handler: RemovalProgressHandler {
        { [self] step in
            lock.lock()
            storage.append(step)
            lock.unlock()
        }
    }
}

/// Everything a view model published as its removal progress, in order.
@MainActor
final class RemovalProgressLog {
    private(set) var values: [RemovalProgress?] = []
    private var subscription: AnyCancellable?

    init(_ publisher: Published<RemovalProgress?>.Publisher) {
        subscription = publisher.sink { [weak self] in self?.values.append($0) }
    }

    /// What was shown at some point.
    var shown: [RemovalProgress] { values.compactMap { $0 } }

    /// The stages shown, without repeats.
    var stages: [RemovalProgress.Stage] {
        shown.map(\.stage).reduce(into: []) { result, stage in
            if result.last != stage { result.append(stage) }
        }
    }

    /// Whether the last thing published was "nothing is being removed".
    var endedEmpty: Bool {
        if case .some(.none) = values.last { return true }
        return false
    }
}
