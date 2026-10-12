import XCTest
@testable import TwanClean

final class AppMatcherTests: XCTestCase {
    private func matcher(_ sensitivity: SearchSensitivity, app: InstalledApp = makeApp()) -> AppMatcher {
        AppMatcher(app: app, sensitivity: sensitivity)
    }

    func testStrictMatchesExactNamesOnly() {
        let strict = matcher(.strict)
        XCTAssertEqual(strict.match("com.example.photoeditor"), .bundleIdentifier)
        XCTAssertEqual(strict.match("com.example.photoeditor.plist"), .bundleIdentifier)
        XCTAssertEqual(strict.match("com.example.PhotoEditor.savedState"), .bundleIdentifier)
        XCTAssertEqual(strict.match("Photo Editor"), .displayName)
        XCTAssertEqual(strict.match("group.com.example.photoeditor"), .bundleIdentifier)
        XCTAssertEqual(strict.match("ABCDE12345.com.example.photoeditor"), .bundleIdentifier)
        XCTAssertNil(strict.match("PhotoEditorHelper"))
        XCTAssertNil(strict.match("ABCDE12345.com.example.shared"))
    }

    func testEnhancedMatchesContainedNamesAndTeamContainers() {
        let enhanced = matcher(.enhanced)
        XCTAssertEqual(enhanced.match("PhotoEditorHelper"), .displayName)
        XCTAssertEqual(enhanced.match("ABCDE12345.com.example.shared"), .teamIdentifier)
        XCTAssertNil(enhanced.match("com.other.app"))
    }

    func testDeveloperNameOnlyMatchesInDeepMode() {
        let app = makeApp(name: "Lightroom", bundleIdentifier: "com.adobe.lightroom", team: nil)
        XCTAssertNil(matcher(.enhanced, app: app).match("Adobe Common"))
        XCTAssertEqual(matcher(.deep, app: app).match("Adobe Common"), .developerName)
    }

    func testShortNamesNeverMatch() {
        let app = makeApp(name: "SSH", bundleIdentifier: "io.ssh", team: nil)
        for sensitivity in SearchSensitivity.allCases {
            XCTAssertNil(matcher(sensitivity, app: app).match(".ssh"), "\(sensitivity)")
            XCTAssertNil(matcher(sensitivity, app: app).match("ssh"), "\(sensitivity)")
        }
    }

    func testHelperSuffixAndVersionAreStripped() {
        let helper = makeApp(name: "Sync 3", bundleIdentifier: "com.vendor.sync.agent.helper", team: nil)
        XCTAssertEqual(matcher(.enhanced, app: helper).match("com.vendor.sync.agent.cache"), .baseBundleIdentifier)
        // "Studio 2 Pro 12": only the version-stripped "Studio 2 Pro" is in the name below.
        let versioned = makeApp(name: "Studio 2 Pro 12", bundleIdentifier: "com.vendor.s2p", team: nil)
        XCTAssertEqual(matcher(.enhanced, app: versioned).match("Studio 2 Pro Settings"), .versionStrippedName)
    }

    func testOverrideExcludesAndIncludes() {
        let chrome = makeApp(name: "Google Chrome", bundleIdentifier: "com.google.Chrome", team: nil)
        let enhanced = matcher(.enhanced, app: chrome)
        XCTAssertNil(enhanced.match("com.googlecode.iterm2"))
        XCTAssertEqual(enhanced.match("Chrome Remote Desktop"), .override)
    }

    func testSingleWordOverrideMatchesAnyComponent() {
        XCTAssertNotNil(AppOverride.matching("com.jetbrains.intellij"))
        XCTAssertNil(AppOverride.matching("com.example.jetbrainsish"))
    }

    func testIgnoredPrefixesNeverMatch() {
        let app = makeApp(name: "Reminders Pro", bundleIdentifier: "com.example.reminderspro", team: nil)
        XCTAssertNil(matcher(.enhanced, app: app).match("Reminders Pro Data"))
    }
}
