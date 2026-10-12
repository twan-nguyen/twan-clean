import XCTest
@testable import TwanClean

final class RunningProcessMatchTests: XCTestCase {
    private let appID = "eu.vendor.Stats"
    private let appPath = "/Applications/Stats.app"

    private func belongs(_ identifier: String?, _ path: String?) -> Bool {
        UninstallerViewModel.belongs(bundleIdentifier: identifier, path: path, to: appID, at: appPath)
    }

    func testTheAppAndItsHelpersBelongToIt() {
        XCTAssertTrue(belongs(appID, "/Applications/Stats.app"))
        XCTAssertTrue(belongs(appID, "/Users/someone/Downloads/Stats.app"), "a copy elsewhere is the same app")
        XCTAssertTrue(belongs("eu.vendor.Stats.LaunchAtLogin", "/Applications/Stats.app/Contents/Library/LoginItems/Helper.app"))
        XCTAssertTrue(belongs(nil, "/Applications/Stats.app/Contents/MacOS/smc-reader"))
        XCTAssertTrue(belongs("eu.vendor.renamed", "/Applications/Stats.app"))
        XCTAssertTrue(belongs(nil, "/applications/stats.APP/Contents/MacOS/Stats"), "the file system ignores case")
    }

    func testOtherProcessesDoNotBelongToIt() {
        XCTAssertFalse(belongs("eu.vendor.StatsPro", "/Applications/Stats Pro.app"))
        XCTAssertFalse(belongs(nil, "/Applications/Stats.app.backup/Contents/MacOS/Stats"))
        XCTAssertFalse(belongs(nil, "/Applications/StatsHelper"))
        XCTAssertFalse(belongs("com.apple.finder", "/System/Library/CoreServices/Finder.app"))
        XCTAssertFalse(belongs(nil, nil))
    }
}
