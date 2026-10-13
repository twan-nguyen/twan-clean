import Foundation

struct ProcessResult: Sendable {
    let exitedNormally: Bool
    let status: Int32
    let output: Data
    let errorOutput: Data
    let timedOut: Bool

    var succeeded: Bool { exitedNormally && status == 0 && !timedOut }

    var outputText: String {
        String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var errorText: String {
        String(decoding: errorOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Runs a program with arguments passed directly, never through a shell.
///
/// Output goes to private temporary files rather than pipes. A pipe fills up
/// when a program writes a lot before it is read, and a child process the
/// program leaves behind can hold a pipe open forever; files avoid both.
enum ProcessRunner {
    /// Nil when the program could not be started. A program still running at
    /// the timeout, or when the calling task is cancelled, is asked to stop
    /// and killed if it has not after `terminationGrace` seconds.
    static func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil,
                    timeout: TimeInterval? = nil, terminationGrace: TimeInterval = 2) async -> ProcessResult? {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TwanClean-process-\(UUID().uuidString)", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                        attributes: [.posixPermissions: 0o700])) != nil else {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        let outputURL = folder.appendingPathComponent("stdout")
        let errorURL = folder.appendingPathComponent("stderr")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              FileManager.default.createFile(atPath: errorURL.path, contents: nil),
              let outputHandle = try? FileHandle(forWritingTo: outputURL),
              let errorHandle = try? FileHandle(forWritingTo: errorURL) else { return nil }
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        let stopper = Stopper(process, grace: terminationGrace)
        let outcome = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Outcome, Never>) in
                let resumer = ResumeOnce(continuation)
                process.terminationHandler = { process in
                    resumer.resume(.finished(normally: process.terminationReason == .exit, status: process.terminationStatus))
                }
                do {
                    try process.run()
                } catch {
                    resumer.resume(.notStarted)
                    return
                }
                // A cancellation that arrived before the program started.
                stopper.startedRunning()
                if let timeout {
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        stopper.stop()
                        resumer.resume(.timedOut)
                    }
                }
            }
        } onCancel: {
            stopper.stop()
        }

        let output = (try? Data(contentsOf: outputURL)) ?? Data()
        let errorOutput = (try? Data(contentsOf: errorURL)) ?? Data()
        switch outcome {
        case .notStarted:
            return nil
        case .timedOut:
            return ProcessResult(exitedNormally: false, status: -1, output: output, errorOutput: errorOutput, timedOut: true)
        case .finished(let normally, let status):
            return ProcessResult(exitedNormally: normally, status: status, output: output, errorOutput: errorOutput,
                                 timedOut: false)
        }
    }

    private enum Outcome: Sendable {
        case notStarted
        case timedOut
        case finished(normally: Bool, status: Int32)
    }

    /// Stops a program politely with SIGTERM, then with SIGKILL if it ignores
    /// that. Safe to call from any thread and any number of times.
    private final class Stopper: @unchecked Sendable {
        private let process: Process
        private let grace: TimeInterval
        private let lock = NSLock()
        private var stopRequested = false
        private var running = false

        init(_ process: Process, grace: TimeInterval) {
            self.process = process
            self.grace = grace
        }

        func startedRunning() {
            lock.lock()
            running = true
            let pending = stopRequested
            lock.unlock()
            if pending { terminate() }
        }

        func stop() {
            lock.lock()
            let first = !stopRequested
            stopRequested = true
            let started = running
            lock.unlock()
            if first, started { terminate() }
        }

        private func terminate() {
            guard process.isRunning else { return }
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + grace) {
                // `isRunning` is checked again so a pid that was reused after
                // a normal exit is never signalled.
                if self.process.isRunning { kill(self.process.processIdentifier, SIGKILL) }
            }
        }
    }

    /// Resumes a continuation exactly once, whichever of exit or timeout
    /// comes first.
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Outcome, Never>?

        init(_ continuation: CheckedContinuation<Outcome, Never>) {
            self.continuation = continuation
        }

        func resume(_ value: Outcome) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
        }
    }
}
