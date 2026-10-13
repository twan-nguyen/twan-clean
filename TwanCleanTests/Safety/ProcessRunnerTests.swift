import XCTest
@testable import TwanClean

private let shellURL = URL(fileURLWithPath: "/bin/sh")

final class ProcessRunnerTests: XCTestCase {
    private var tree: TemporaryTree!

    override func setUpWithError() throws {
        tree = try TemporaryTree()
    }

    override func tearDown() {
        tree = nil
    }

    /// Whether a process with this id still exists.
    private func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    private func waitUntilGone(_ pid: pid_t, within seconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if !isAlive(pid) { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return !isAlive(pid)
    }

    private func recordedPid(_ file: URL) async throws -> pid_t {
        for _ in 0..<100 {
            if let text = try? String(contentsOf: file, encoding: .utf8),
               let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return pid
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw XCTSkip("the test program never recorded its pid")
    }

    func testCapturesOutputAndStatus() async throws {
        let run = await ProcessRunner.run(shellURL, ["-c", "echo out; echo err >&2; exit 3"])
        let result = try XCTUnwrap(run)
        XCTAssertEqual(result.outputText, "out")
        XCTAssertEqual(result.errorText, "err")
        XCTAssertEqual(result.status, 3)
        XCTAssertFalse(result.succeeded)
    }

    func testProgramIgnoringTermIsKilledAfterTheGracePeriod() async throws {
        let pidFile = tree.url("pid")
        // `exec` keeps the ignored SIGTERM with the sleeping process itself.
        let script = "trap '' TERM; echo $$ > '\(pidFile.path)'; exec sleep 30"
        let started = Date()

        let run = await ProcessRunner.run(shellURL, ["-c", script], timeout: 0.5, terminationGrace: 0.3)
        let result = try XCTUnwrap(run)

        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        let pid = try await recordedPid(pidFile)
        let gone = await waitUntilGone(pid, within: 5)
        XCTAssertTrue(gone, "the program ignoring SIGTERM must be killed")
    }

    func testCancellingTheTaskStopsTheProgram() async throws {
        let pidFile = tree.url("pid")
        let script = "echo $$ > '\(pidFile.path)'; exec sleep 30"
        let task = Task { await ProcessRunner.run(shellURL, ["-c", script]) }

        let pid = try await recordedPid(pidFile)
        task.cancel()
        let result = await task.value

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.succeeded, false)
        let gone = await waitUntilGone(pid, within: 5)
        XCTAssertTrue(gone, "cancelling must terminate the child")
    }

    func testCancellingEscalatesForAProgramIgnoringTerm() async throws {
        let pidFile = tree.url("pid")
        let script = "trap '' TERM; echo $$ > '\(pidFile.path)'; exec sleep 30"
        let task = Task { await ProcessRunner.run(shellURL, ["-c", script], terminationGrace: 0.3) }

        let pid = try await recordedPid(pidFile)
        task.cancel()
        _ = await task.value

        let gone = await waitUntilGone(pid, within: 5)
        XCTAssertTrue(gone)
    }

    func testAlreadyCancelledTaskDoesNotLeaveTheProgramRunning() async throws {
        let pidFile = tree.url("pid")
        let script = "echo $$ > '\(pidFile.path)'; exec sleep 30"
        let started = Date()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await ProcessRunner.run(shellURL, ["-c", script])
        }

        let result = await task.value

        // Left running, the program would keep the call waiting for 30 seconds.
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        XCTAssertEqual(result?.succeeded, false)
    }
}
