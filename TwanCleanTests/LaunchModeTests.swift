import XCTest
@testable import TwanClean

final class LaunchModeTests: XCTestCase {
    func testPlainLaunchIsGUI() {
        XCTAssertEqual(LaunchMode(arguments: ["/Applications/TwanClean.app/Contents/MacOS/TwanClean"]), .gui)
    }

    func testScheduledRunFlagSelectsHeadlessMode() {
        XCTAssertEqual(LaunchMode(arguments: ["TwanClean", "--scheduled-run"]), .scheduledRun)
    }

    func testUnrelatedFlagsStayGUI() {
        XCTAssertEqual(LaunchMode(arguments: ["TwanClean", "-NSDocumentRevisionsDebugMode", "YES"]), .gui)
    }

    func testFlagAsExecutablePathIsIgnored() {
        XCTAssertEqual(LaunchMode(arguments: ["--scheduled-run"]), .gui)
    }
}
