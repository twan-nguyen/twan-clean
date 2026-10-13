import XCTest
@testable import TwanClean

final class RemovalProgressTests: XCTestCase {
    private var tree: TemporaryTree!
    private var home: FakeHome!

    override func setUpWithError() throws {
        tree = try TemporaryTree()
        home = try FakeHome(tree: tree)
    }

    override func tearDown() {
        home = nil
        tree = nil
    }

    // MARK: - RemovalService

    func testEveryRequestIsReportedWhetherRemovedRefusedOrAlreadyGone() async throws {
        let removed = try tree.makeFile("home/Library/Caches/com.example/blob", bytes: 2048)
        let refused = try tree.makeFile("home/Documents/keep.txt")
        let vanished = try tree.makeFile("home/Library/Caches/vanished")
        let requests = [try home.request(removed, .regenerableCache),
                        try home.request(refused, .regenerableCache),
                        try home.request(vanished, .regenerableCache)]
        try FileManager.default.removeItem(at: vanished)
        let recorder = StepRecorder()

        let service = try home.removalService()

        let report = await service.remove(requests, progress: recorder.handler)

        XCTAssertEqual(report.removed.count, 1)
        XCTAssertEqual(report.refused.count, 1)
        XCTAssertEqual(report.alreadyGone.count, 1)
        XCTAssertTrue(tree.exists(refused), "a refused item is left alone")
        // Before each request, and once more when the last one is settled.
        XCTAssertEqual(recorder.steps.map(\.completed), [0, 1, 2, 3])
        XCTAssertEqual(Set(recorder.steps.map(\.total)), [3])
        XCTAssertEqual(recorder.steps.map(\.url), requests.map(\.url) + [requests[2].url])
    }

    func testReportingProgressDoesNotChangeWhatIsRemoved() async throws {
        let first = try tree.makeFile("home/Library/Caches/a/blob")
        let second = try tree.makeFile("home/Library/Caches/b/blob")
        let requests = [try home.request(first.deletingLastPathComponent(), .regenerableCache),
                        try home.request(second.deletingLastPathComponent(), .regenerableCache)]
        let service = try home.removalService()

        let report = await service.remove(requests, progress: StepRecorder().handler)

        XCTAssertEqual(report.removed.map(\.url), requests.map(\.url), "in the order given")
        XCTAssertFalse(tree.exists(first))
        XCTAssertFalse(tree.exists(second))
    }

    func testNothingIsReportedForNoRequests() async throws {
        let recorder = StepRecorder()
        let service = try home.removalService()

        let report = await service.remove([], progress: recorder.handler)

        XCTAssertTrue(report.removed.isEmpty)
        XCTAssertTrue(recorder.steps.isEmpty)
    }

    func testACancelledRemovalReportsAndRemovesNothing() async throws {
        let item = try tree.makeFile("home/Library/Caches/com.example/blob")
        let request = try home.request(item.deletingLastPathComponent(), .regenerableCache)
        let service = try home.removalService()
        let recorder = StepRecorder()

        let task = Task { () -> RemovalReport in
            while !Task.isCancelled { await Task.yield() }
            return await service.remove([request], progress: recorder.handler)
        }
        task.cancel()
        let report = await task.value

        XCTAssertTrue(report.removed.isEmpty)
        XCTAssertTrue(recorder.steps.isEmpty)
        XCTAssertTrue(tree.exists(item))
    }

    // MARK: - PrivilegedRemover

    func testPrivilegedRemovalSettlesEveryRequestAndNeverRunsOsascript() async throws {
        let blocked = try tree.makeFile("home/Library/Caches/blocked/blob")
        let outside = try tree.makeFile("home/Documents/keep.txt")
        let vanished = try tree.makeFile("home/Library/Caches/vanished")
        let requests = [try home.request(blocked.deletingLastPathComponent(), .regenerableCache),
                        try home.request(outside, .regenerableCache),
                        try home.request(vanished, .regenerableCache)]
        try FileManager.default.removeItem(at: vanished)
        let recorder = StepRecorder()
        let succeeded = ProcessResult(exitedNormally: true, status: 0, output: Data(), errorOutput: Data(), timedOut: false)
        // Stands in for the administrator command: removes the folder as this user.
        let remover = PrivilegedRemover(
            service: RemovalService(policy: home.policy), prompt: "x",
            runScript: { _ in
                try? FileManager.default.removeItem(at: blocked.deletingLastPathComponent())
                return succeeded
            },
            recycle: { _ in [:] })

        let report = await remover.remove(requests, progress: recorder.handler)

        XCTAssertEqual(report.removed.count, 1)
        XCTAssertEqual(report.refused.count, 1)
        XCTAssertEqual(report.alreadyGone.count, 1)
        XCTAssertEqual(recorder.steps.map(\.completed), [1, 2, 3])
        XCTAssertEqual(Set(recorder.steps.map(\.total)), [3])
        XCTAssertEqual(Set(recorder.steps.map(\.url.path)), Set(requests.map(\.url.path)))
    }

    // MARK: - ProgressThrottle

    private final class FakeClock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: TimeInterval = 100
        var now: TimeInterval {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        func advance(_ seconds: TimeInterval) {
            lock.lock()
            value += seconds
            lock.unlock()
        }
    }

    private func step(_ completed: Int, of total: Int) -> RemovalStep {
        RemovalStep(completed: completed, total: total, url: URL(fileURLWithPath: "/x/\(completed)"))
    }

    func testAThousandItemsInAFlashPassOnlyTheFirstAndTheLastStep() {
        let clock = FakeClock()
        let throttle = ProgressThrottle(interval: 0.05, everyStepUpTo: 20, clock: { clock.now })

        let passed = (0...1000).filter { throttle.passes(step($0, of: 1000)) }

        XCTAssertEqual(passed, [0, 1000])
    }

    func testStepsPassOnceTheIntervalHasGoneBy() {
        let clock = FakeClock()
        let throttle = ProgressThrottle(interval: 0.05, everyStepUpTo: 20, clock: { clock.now })

        XCTAssertTrue(throttle.passes(step(1, of: 500)))
        clock.advance(0.02)
        XCTAssertFalse(throttle.passes(step(2, of: 500)))
        clock.advance(0.04)
        XCTAssertTrue(throttle.passes(step(3, of: 500)))
    }

    func testAFewItemsAlwaysPass() {
        let clock = FakeClock()
        let throttle = ProgressThrottle(interval: 0.05, everyStepUpTo: 20, clock: { clock.now })

        XCTAssertTrue((0...20).allSatisfy { throttle.passes(step($0, of: 20)) })
    }

    // MARK: - RemovalProgressPublishing

    @MainActor
    private final class Publisher: RemovalProgressPublishing {
        var removalProgress: RemovalProgress?
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<400 where !condition() { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    @MainActor
    func testStepsUpdateTheCountAndTheCurrentItemAndKeepTheStage() async {
        let publisher = Publisher()
        let handler = publisher.beginRemoval(.movingToTrash, total: 5)
        XCTAssertEqual(publisher.removalProgress?.total, 5)
        XCTAssertEqual(publisher.removalProgress?.completed, 0)

        handler(step(3, of: 5))
        await waitUntil { publisher.removalProgress?.completed == 3 }
        publisher.setRemovalStage(.cleaning)

        XCTAssertEqual(publisher.removalProgress?.completed, 3)
        XCTAssertEqual(publisher.removalProgress?.currentName, "3")
        XCTAssertEqual(publisher.removalProgress?.stage, .cleaning)
        XCTAssertEqual(publisher.removalProgress?.fraction, 0.6)
    }

    @MainActor
    func testEndingARemovalClearsItAndDropsStepsThatArriveLate() async {
        let publisher = Publisher()
        let handler = publisher.beginRemoval(.movingToTrash, total: 5)
        publisher.endRemoval()
        XCTAssertNil(publisher.removalProgress)

        handler(step(5, of: 5))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(publisher.removalProgress)
    }

    @MainActor
    func testAStepFromAnEarlierRunNeverShowsOnTheNextOne() async {
        let publisher = Publisher()
        let earlier = publisher.beginRemoval(.movingToTrash, total: 9)
        publisher.endRemoval()
        _ = publisher.beginRemoval(.waitingForPassword, total: 2)

        earlier(step(7, of: 9))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(publisher.removalProgress?.completed, 0)
        XCTAssertEqual(publisher.removalProgress?.total, 2)
    }

    @MainActor
    func testOnlyCountingStagesHaveAFraction() {
        XCTAssertNil(RemovalProgress(stage: .waitingForPassword, completed: 1, total: 2).fraction)
        XCTAssertNil(RemovalProgress(stage: .quittingApp("Editor"), total: 2).fraction)
        XCTAssertNil(RemovalProgress(stage: .stoppingServices, total: 2).fraction)
        XCTAssertNil(RemovalProgress(stage: .cleaning, total: 0).fraction)
        XCTAssertEqual(RemovalProgress(stage: .movingToTrash, completed: 1, total: 4).fraction, 0.25)
    }
}
