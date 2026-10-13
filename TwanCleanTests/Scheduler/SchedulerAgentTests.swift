import ServiceManagement
import XCTest
@testable import TwanClean

/// Stands in for `SMAppService` so no test registers a real login item.
private final class FakeService: SchedulerService {
    var status: SMAppService.Status
    /// What `register()` does: succeed, or fail and optionally move to another status.
    var registerError: Error?
    var statusAfterFailedRegister: SMAppService.Status?
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCalls += 1
        if let registerError {
            if let statusAfterFailedRegister { status = statusAfterFailedRegister }
            throw registerError
        }
        status = .enabled
    }

    func unregister() throws {
        unregisterCalls += 1
        status = .notRegistered
    }
}

final class SchedulerAgentTests: XCTestCase {
    private struct Refused: Error {}

    private func store(enabled: Bool) throws -> ScheduleStore {
        let tree = try TemporaryTree()
        retained.append(tree)
        let store = ScheduleStore(folder: tree.url("support"))
        var settings = ScheduleSettings()
        settings.isEnabled = enabled
        try store.save(settings)
        return store
    }

    private var retained: [TemporaryTree] = []

    override func tearDown() {
        retained = []
    }

    func testEnablingRegistersTheTask() throws {
        let service = FakeService(status: .notRegistered)
        try SchedulerAgent.setEnabled(true, service: service)
        XCTAssertEqual(service.registerCalls, 1)
    }

    func testWaitingForApprovalIsNotAFailure() throws {
        let service = FakeService(status: .notRegistered)
        service.registerError = Refused()
        service.statusAfterFailedRegister = .requiresApproval

        XCTAssertNoThrow(try SchedulerAgent.setEnabled(true, service: service))
        XCTAssertEqual(service.status, .requiresApproval)
    }

    func testOtherRegistrationFailuresAreThrown() {
        let service = FakeService(status: .notRegistered)
        service.registerError = Refused()
        XCTAssertThrowsError(try SchedulerAgent.setEnabled(true, service: service))
    }

    func testDisablingUnregistersOnlyWhatIsRegistered() throws {
        let registered = FakeService(status: .enabled)
        try SchedulerAgent.setEnabled(false, service: registered)
        XCTAssertEqual(registered.unregisterCalls, 1)

        let absent = FakeService(status: .notRegistered)
        try SchedulerAgent.setEnabled(false, service: absent)
        XCTAssertEqual(absent.unregisterCalls, 0)
    }

    func testEnabledScheduleWithoutATaskIsRegisteredAgain() throws {
        let service = FakeService(status: .notRegistered)
        let result = SchedulerAgent.reconcile(store: try store(enabled: true), service: service, isJobLoaded: { true })
        XCTAssertEqual(result, .registeredAgain)
        XCTAssertEqual(service.registerCalls, 1)
    }

    func testTaskListedButNotLoadedIsRegisteredAgain() throws {
        // What Homebrew's launchctl remove leaves behind during an upgrade.
        let service = FakeService(status: .enabled)
        let result = SchedulerAgent.reconcile(store: try store(enabled: true), service: service, isJobLoaded: { false })
        XCTAssertEqual(result, .registeredAgain)
        XCTAssertEqual(service.unregisterCalls, 1)
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertEqual(service.status, .enabled)
    }

    func testHealthyTaskIsLeftAlone() throws {
        let service = FakeService(status: .enabled)
        let result = SchedulerAgent.reconcile(store: try store(enabled: true), service: service, isJobLoaded: { true })
        XCTAssertEqual(result, .consistent)
        XCTAssertEqual(service.registerCalls + service.unregisterCalls, 0)
    }

    func testDisabledScheduleRegistersNothing() throws {
        let service = FakeService(status: .notRegistered)
        let result = SchedulerAgent.reconcile(store: try store(enabled: false), service: service, isJobLoaded: { false })
        XCTAssertEqual(result, .consistent)
        XCTAssertEqual(service.registerCalls, 0)
    }

    func testApprovalPendingIsReportedNotRetried() throws {
        let service = FakeService(status: .requiresApproval)
        let result = SchedulerAgent.reconcile(store: try store(enabled: true), service: service, isJobLoaded: { false })
        XCTAssertEqual(result, .awaitingApproval)
        XCTAssertEqual(service.registerCalls, 0)
    }

    func testDamagedScheduleIsSetAsideAndTheTaskRemoved() throws {
        let tree = try TemporaryTree()
        try tree.makeDirectory("support")
        try Data("{ not json".utf8).write(to: tree.url("support/schedule.json"))
        let service = FakeService(status: .enabled)

        let result = SchedulerAgent.reconcile(store: ScheduleStore(folder: tree.url("support")), service: service,
                                              isJobLoaded: { true })

        XCTAssertEqual(result, .scheduleDiscarded)
        XCTAssertEqual(service.unregisterCalls, 1)
        XCTAssertTrue(tree.exists(tree.url("support/schedule.json.damaged")))
        XCTAssertFalse(tree.exists(tree.url("support/schedule.json")))
    }
}
