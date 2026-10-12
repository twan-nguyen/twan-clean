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
}
