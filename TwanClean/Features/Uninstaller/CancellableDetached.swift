import Foundation

/// Runs blocking work off the calling actor and stops it when the awaiting
/// task is cancelled. A plain `Task.detached` does not inherit cancellation,
/// so a cancelled scan would otherwise run to the end.
func runDetached<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    let task = Task.detached(operation: work)
    return await withTaskCancellationHandler {
        await task.value
    } onCancel: {
        task.cancel()
    }
}
