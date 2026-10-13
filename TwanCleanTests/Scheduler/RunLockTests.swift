import XCTest
@testable import TwanClean

final class RunLockTests: XCTestCase {
    func testSecondHolderIsRefusedUntilTheFirstLetsGo() throws {
        let tree = try TemporaryTree()
        let file = tree.url("locks/scan.lock")
        var first = RunLock.acquire(at: file)
        XCTAssertNotNil(first)
        XCTAssertNil(RunLock.acquire(at: file))
        first = nil
        XCTAssertNotNil(RunLock.acquire(at: file))
        withExtendedLifetime(first) {}
    }

    func testHeldLockIsBusy() throws {
        let tree = try TemporaryTree()
        let file = tree.url("locks/scan.lock")
        let held = try XCTUnwrap(RunLock.acquire(at: file))
        guard case .busy = RunLock.attempt(at: file) else { return XCTFail("expected busy") }
        withExtendedLifetime(held) {}
    }

    func testUnopenableLockFileIsUnavailableNotBusy() throws {
        let tree = try TemporaryTree()
        // A folder where the lock file should be cannot be opened for writing.
        let file = try tree.makeDirectory("locks/scan.lock")
        guard case .unavailable = RunLock.attempt(at: file) else { return XCTFail("expected unavailable") }
        XCTAssertNil(RunLock.acquire(at: file))
    }

    func testUncreatableFolderIsUnavailable() throws {
        let tree = try TemporaryTree()
        let blocker = try tree.makeFile("not-a-folder")
        guard case .unavailable = RunLock.attempt(at: blocker.appendingPathComponent("scan.lock")) else {
            return XCTFail("expected unavailable")
        }
    }
}
