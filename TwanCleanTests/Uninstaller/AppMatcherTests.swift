import XCTest
@testable import TwanClean

final class AppMatcherTests: XCTestCase {
    private func matcher(_ sensitivity: SearchSensitivity, app: InstalledApp = makeApp()) -> AppMatcher {
        AppMatcher(app: app, sensitivity: sensitivity)
    }

    func testStrictMatchesExactNamesOnly() {
        let strict = matcher(.strict)
        XCTAssertEqual(strict.match("com.example.photoeditor")?.tier, .bundleIdentifier)
        XCTAssertEqual(strict.match("com.example.photoeditor.plist")?.tier, .bundleIdentifier)
        XCTAssertEqual(strict.match("com.example.PhotoEditor.savedState")?.tier, .bundleIdentifier)
        XCTAssertEqual(strict.match("Photo Editor")?.tier, .displayName)
        XCTAssertEqual(strict.match("group.com.example.photoeditor")?.tier, .bundleIdentifier)
        XCTAssertEqual(strict.match("ABCDE12345.com.example.photoeditor")?.tier, .bundleIdentifier)
        XCTAssertNil(strict.match("PhotoEditorHelper"))
        XCTAssertNil(strict.match("ABCDE12345.com.example.shared"))
    }

    func testEnhancedMatchesContainedNamesAndTeamContainers() {
        let enhanced = matcher(.enhanced)
        XCTAssertEqual(enhanced.match("PhotoEditorHelper")?.tier, .displayName)
        XCTAssertEqual(enhanced.match("ABCDE12345.com.example.shared")?.tier, .teamIdentifier)
        XCTAssertNil(enhanced.match("com.other.app"))
    }

    func testDeveloperNameOnlyMatchesInDeepMode() {
        let app = makeApp(name: "Lightroom", bundleIdentifier: "com.adobe.lightroom", team: nil)
        XCTAssertNil(matcher(.enhanced, app: app).match("Adobe Common"))
        XCTAssertEqual(matcher(.deep, app: app).match("Adobe Common")?.tier, .developerName)
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
        XCTAssertEqual(matcher(.enhanced, app: helper).match("com.vendor.sync.agent.cache")?.tier, .baseBundleIdentifier)
        // "Studio 2 Pro 12": only the version-stripped "Studio 2 Pro" is in the name below.
        let versioned = makeApp(name: "Studio 2 Pro 12", bundleIdentifier: "com.vendor.s2p", team: nil)
        XCTAssertEqual(matcher(.enhanced, app: versioned).match("Studio 2 Pro Settings")?.tier, .versionStrippedName)
    }

    func testOverrideExcludesAndIncludes() {
        let chrome = makeApp(name: "Google Chrome", bundleIdentifier: "com.google.Chrome", team: nil)
        let enhanced = matcher(.enhanced, app: chrome)
        XCTAssertNil(enhanced.match("com.googlecode.iterm2"))
        // A separate app; Chrome no longer claims every name with "chrome" in it.
        XCTAssertNil(enhanced.match("Chrome Remote Desktop"))
    }

    func testSingleWordOverrideMatchesAnyComponent() {
        XCTAssertNotNil(AppOverride.matching("com.jetbrains.intellij"))
        XCTAssertNil(AppOverride.matching("com.example.jetbrainsish"))
    }

    func testIgnoredPrefixesNeverMatch() {
        let app = makeApp(name: "Reminders Pro", bundleIdentifier: "com.example.reminderspro", team: nil)
        XCTAssertNil(matcher(.enhanced, app: app).match("Reminders Pro Data"))
    }

    func testStrictMatchesAreMarkedExactAndContainedOnesAreNot() {
        XCTAssertEqual(matcher(.enhanced).match("com.example.photoeditor.plist")?.isExact, true)
        XCTAssertEqual(matcher(.enhanced).match("PhotoEditorHelper")?.isExact, false)
    }

    func testBundleIdentifierMustStandOnItsOwn() {
        let chrome = makeApp(name: "Google Chrome", bundleIdentifier: "com.google.Chrome", team: nil)
        let enhanced = matcher(.enhanced, app: chrome)
        XCTAssertEqual(enhanced.match("com.google.Chrome.helper")?.tier, .bundleIdentifier)
        // Still caught by the looser name rules, but never as the identifier,
        // and another installed app that claims it more specifically wins.
        XCTAssertNotEqual(enhanced.match("com.google.ChromeBeta")?.tier, .bundleIdentifier)
    }

    func testBetaAppNeverClaimsTheStableAppsFiles() {
        let beta = makeApp(name: "Google Chrome Beta", bundleIdentifier: "com.google.Chrome.beta", team: nil)
        for sensitivity in SearchSensitivity.allCases {
            let matcher = matcher(sensitivity, app: beta)
            XCTAssertNil(matcher.match("Chrome"), "\(sensitivity)")
            XCTAssertNil(matcher.match("com.google.Chrome.plist"), "\(sensitivity)")
        }
    }

    func testOverrideTermsAreIgnoredInStrictMode() {
        let zoom = makeApp(name: "zoom.us", bundleIdentifier: "us.zoom.xos", team: nil)
        XCTAssertNil(matcher(.strict, app: zoom).match("ZoomOpener"))
        XCTAssertEqual(matcher(.enhanced, app: zoom).match("ZoomOpener")?.tier, .override)
    }

    func testNamesStartingWithADigitKeepIt() {
        let app = makeApp(name: "1Password", bundleIdentifier: "com.agilebits.onepassword", team: nil)
        let enhanced = matcher(.enhanced, app: app)
        XCTAssertNil(enhanced.match("Passwords"))
        XCTAssertNil(enhanced.match("PasswordStore"))
        XCTAssertNil(enhanced.match("Apple Passwords Export"))
        XCTAssertEqual(enhanced.match("1Password")?.isExact, true)
        XCTAssertEqual(enhanced.match("1Password Data")?.isCertain, false)
    }

    func testNamesContainingTheAppNameAreNeverCertain() {
        let enhanced = matcher(.enhanced)
        XCTAssertEqual(enhanced.match("Photo Editor")?.isCertain, true)
        XCTAssertEqual(enhanced.match("com.example.photoeditor.plist")?.isCertain, true)
        XCTAssertEqual(enhanced.match("com.example.photoeditor.helper")?.isCertain, true, "contains the whole identifier")
        XCTAssertEqual(enhanced.match("PhotoEditorHelper")?.isCertain, false)
        XCTAssertEqual(enhanced.match("Photo Editor Projects Cache")?.isCertain, false)
    }

    func testOverrideTermsAreNeverCertainUnlessTheNameIsExact() {
        let zoom = makeApp(name: "zoom.us", bundleIdentifier: "us.zoom.xos", team: nil)
        let match = matcher(.enhanced, app: zoom).match("ZoomOpener")
        XCTAssertEqual(match?.tier, .override)
        XCTAssertEqual(match?.isCertain, false)
        let jetbrains = makeApp(name: "IntelliJ IDEA", bundleIdentifier: "com.jetbrains.intellij", team: nil)
        XCTAssertEqual(matcher(.enhanced, app: jetbrains).match("jcef_12345")?.isCertain, false)
    }

    func testOverrideFoldersBelongOnlyToTheAppWithTheExactIdentifier() {
        let chrome = makeApp(name: "Google Chrome", bundleIdentifier: "com.google.Chrome", team: nil)
        let beta = makeApp(name: "Google Chrome Beta", bundleIdentifier: "com.google.Chrome.beta", team: nil)
        XCTAssertEqual(matcher(.enhanced, app: chrome).extraFolders,
                       ["Library/Application Support/Google/Chrome", "Library/Caches/Google/Chrome"])
        XCTAssertTrue(matcher(.enhanced, app: beta).extraFolders.isEmpty)
        XCTAssertTrue(matcher(.enhanced, app: chrome).claims(homeRelativeFolder: "Library/Caches/Google/Chrome"))
    }
}
