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
    /// Nil when the program could not be started.
    static func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil,
                    timeout: TimeInterval? = nil) async -> ProcessResult? {
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

        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<Outcome, Never>) in
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
            if let timeout {
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning { process.terminate() }
                    resumer.resume(.timedOut)
                }
            }
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
