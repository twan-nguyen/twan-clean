import XCTest
@testable import TwanClean

final class PathPolicyTests: XCTestCase {
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

    private func decision(_ url: URL, _ purpose: RemovalPurpose) -> PolicyDecision {
        home.policy.evaluate(url, purpose: purpose)
    }

    /// Compares paths, not URLs: whether Foundation adds a trailing slash to
    /// a folder URL differs between macOS releases.
    private func assertAllowed(_ url: URL, _ purpose: RemovalPurpose,
                               file: StaticString = #filePath, line: UInt = #line) {
        guard case .allowed(let allowed) = decision(url, purpose) else {
            return XCTFail("\(url.path) refused for \(purpose)", file: file, line: line)
        }
        XCTAssertEqual(allowed.path, url.path, file: file, line: line)
    }

    private func assertRefused(_ url: URL, _ purpose: RemovalPurpose, _ reason: RefusalReason,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(decision(url, purpose), .refused(reason), url.path, file: file, line: line)
    }

    // MARK: - Allowed

    func testCacheItemIsAllowedForRegenerableCache() throws {
        let item = try tree.makeFile("home/Library/Caches/com.example.app/data.bin")
        assertAllowed(item, .regenerableCache)
    }

    func testUserFileInDownloadsIsAllowed() throws {
        let item = try tree.makeFile("home/Downloads/movie.mov")
        assertAllowed(item, .userFile)
    }

    func testTrashChildIsAllowedForTrashContents() throws {
        let item = try tree.makeFile("home/.Trash/old.zip")
        assertAllowed(item, .trashContents)
    }

    func testRelativeComponentsAreResolvedBeforeChecking() throws {
        try tree.makeFile("home/.ssh/id_ed25519")
        let sneaky = home.url("Library/Caches/../../.ssh/id_ed25519")
        assertRefused(sneaky, .regenerableCache, .systemLocation)
    }

    // MARK: - Protected roots and system locations

    func testProtectedRootsAreNeverRemovable() {
        for path in ["/", "/System", "/Applications", "/Library", "/Users", "/private/var", "/usr"] {
            for purpose in RemovalPurpose.allCases {
                if case .allowed = decision(URL(fileURLWithPath: path), purpose) {
                    XCTFail("\(path) allowed for \(purpose)")
                }
            }
        }
        for folder in ["", "Library", "Documents", "Downloads", "Desktop", ".Trash"] {
            assertRefused(home.url(folder), .userFile, .protectedRoot)
        }
    }

    func testAllowedTreeRootItselfIsNotRemovable() {
        assertRefused(home.url("Library/Caches"), .regenerableCache, .protectedRoot)
    }

    func testSystemTreesAreRefusedForEveryPurpose() {
        let system = URL(fileURLWithPath: "/System/Library/CoreServices")
        for purpose in RemovalPurpose.allCases {
            assertRefused(system, purpose, .systemLocation)
        }
    }

    func testSystemCheckIgnoresCase() {
        assertRefused(URL(fileURLWithPath: "/system/library/CoreServices"), .appLeftover, .systemLocation)
    }

    func testHighRiskHomeItemsAreRefused() throws {
        for name in SafetyRules.highRiskHomeItemNames {
            try tree.makeFile("home/\(name)/inner")
            assertRefused(home.url(name), .userFile, .systemLocation)
            assertRefused(home.url("\(name)/inner"), .userFile, .systemLocation)
        }
    }

    func testKeychainsAreRefusedForLeftovers() throws {
        let keychain = try tree.makeFile("home/Library/Keychains/login.keychain-db")
        assertRefused(keychain, .appLeftover, .systemLocation)
    }

    // MARK: - Purpose boundaries

    func testSiblingWithSharedPrefixIsOutside() throws {
        let sibling = try tree.makeFile("home/Library/CachesX/file")
        assertRefused(sibling, .regenerableCache, .outsideAllowedArea)
    }

    func testUserFilePurposeCannotReachLibrary() throws {
        let preference = try tree.makeFile("home/Library/Preferences/com.example.plist")
        assertRefused(preference, .userFile, .outsideAllowedArea)
    }

    func testRegenerableCachePurposeCannotReachDocuments() throws {
        let document = try tree.makeFile("home/Documents/thesis.pages")
        assertRefused(document, .regenerableCache, .outsideAllowedArea)
    }

    func testOrphanPurposeRefusesAppleItems() throws {
        let item = try tree.makeDirectory("home/Library/Caches/com.apple.Safari")
        assertRefused(item, .orphan, .appleItem)
    }

    func testAppBundlePurposeRequiresAnAppBundle() {
        assertRefused(URL(fileURLWithPath: "/Applications/readme.txt"), .appBundle, .notAnAppBundle)
        assertAllowed(URL(fileURLWithPath: "/Applications/Example.app"), .appBundle)
    }

    // MARK: - Symlinks

    func testSymlinkedParentCannotEscapeTheAllowedTree() throws {
        let documents = home.url("Documents")
        try tree.makeFile("home/Documents/secret.txt")
        try tree.makeSymlink("home/Library/Caches/escape", to: documents)
        assertRefused(home.url("Library/Caches/escape/secret.txt"), .regenerableCache, .outsideAllowedArea)
    }

    func testSymlinkItselfIsJudgedByItsOwnLocation() throws {
        let link = try tree.makeSymlink("home/Library/Caches/escape", to: home.url("Documents"))
        assertAllowed(link, .regenerableCache)
    }

    func testMissingParentIsUnresolvable() {
        assertRefused(home.url("Library/Caches/missing/child"), .regenerableCache, .unresolvable)
    }

    func testNonFileURLIsRefused() throws {
        assertRefused(try XCTUnwrap(URL(string: "https://example.com/x")), .userFile, .notAFileURL)
    }

    // MARK: - Leftovers, orphans and Apple data

    func testLeftoversNeverIncludeAWholeStandardLibraryFolder() throws {
        try tree.makeDirectory("home/Library/Application Support/com.example.app")
        assertRefused(home.url("Library/Application Support"), .appLeftover, .protectedRoot)
        assertRefused(home.url("Library/Preferences"), .appLeftover, .protectedRoot)
        let own = home.url("Library/Application Support/com.example.app")
        assertAllowed(own, .appLeftover)
    }

    func testCollapsedPathCannotReachAStandardLibraryFolder() throws {
        try tree.makeDirectory("home/Library/Application Support/Foo")
        assertRefused(home.url("Library/Application Support/Foo/.."), .appLeftover, .protectedRoot)
    }

    func testAppleDataIsRefusedForLeftoversAtAnyDepth() throws {
        try tree.makeFile("home/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite")
        assertRefused(home.url("Library/Group Containers/group.com.apple.notes"), .appLeftover, .appleItem)
        assertRefused(home.url("Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"), .appLeftover, .appleItem)
    }

    func testAppleDataIsRefusedForOrphansAtAnyDepth() throws {
        try tree.makeFile("home/Library/Caches/com.apple.Safari/sub/file")
        assertRefused(home.url("Library/Caches/com.apple.Safari/sub"), .orphan, .appleItem)
    }

    func testTeamPrefixedAppleGroupContainersAreRefused() throws {
        let podcasts = try tree.makeDirectory("home/Library/Group Containers/243LU875E5.groups.com.apple.podcasts")
        assertRefused(podcasts, .appLeftover, .appleItem)
        assertAllowed(try tree.makeDirectory("home/Library/Group Containers/ABCDE12345.com.example.suite"), .appLeftover)
    }

    func testAppleDataWithoutAnAppleNameIsRefusedForEveryPurpose() throws {
        for folder in ["Application Support/CallHistoryDB", "Application Support/Knowledge", "Metadata/CoreSpotlight"] {
            let item = try tree.makeDirectory("home/Library/\(folder)")
            for purpose in RemovalPurpose.allCases {
                assertRefused(item, purpose, .systemLocation)
            }
        }
        try tree.makeDirectory("home/Library/Metadata")
        assertRefused(home.url("Library/Metadata"), .appLeftover, .systemLocation)
        for path in ["/Library/Application Support/Apple", "/Library/Application Support/CrashReporter",
                     "/Library/Preferences/OpenDirectory"] {
            assertRefused(URL(fileURLWithPath: path), .appLeftover, .systemLocation)
        }
    }

    func testUsersOwnCrashReportsRemainAnOrphanTarget() throws {
        let reports = try tree.makeDirectory("home/Library/Application Support/CrashReporter/old.crash")
        assertAllowed(reports, .orphan)
    }

    func testNetworkSettingsAreNeverLeftovers() {
        assertRefused(URL(fileURLWithPath: "/Library/Preferences/SystemConfiguration"), .appLeftover, .systemLocation)
    }

    // MARK: - App bundles

    func testAppInsideAnotherAppIsRefused() {
        let nested = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app")
        if case .allowed = decision(nested, .appBundle) {
            XCTFail("nested app allowed")
        }
    }

    // MARK: - Shared temporary folders

    func testOnlyDirectChildrenOfSharedTemporaryFoldersAreRemovable() throws {
        let folder = URL(fileURLWithPath: "/private/tmp/TwanCleanTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        assertAllowed(folder, .regenerableCache)
        assertRefused(folder.appendingPathComponent("inner"), .regenerableCache, .outsideAllowedArea)
    }

    func testMacOSTemporaryItemsAreRefused() {
        assertRefused(URL(fileURLWithPath: "/private/tmp/com.apple.launchd.AbCdEf"), .regenerableCache, .appleItem)
    }

    func testTmpAliasIsResolved() {
        assertRefused(URL(fileURLWithPath: "/tmp/com.apple.launchd.AbCdEf"), .regenerableCache, .appleItem)
        assertRefused(URL(fileURLWithPath: "/tmp"), .regenerableCache, .protectedRoot)
    }

    // MARK: - Unicode

    func testCombiningMarkCannotSlipPastForbiddenTrees() throws {
        try tree.makeDirectory("home/.ssh")
        assertRefused(home.url(".ssh/\u{301}evil"), .userFile, .systemLocation)
    }

    func testNamesFoldTheWayAPFSDoes() throws {
        try tree.makeDirectory("home/.ssh")
        // The volume treats the long s as "s" and the ligature as "st".
        assertRefused(home.url(".\u{17F}sh"), .userFile, .systemLocation)
        assertRefused(home.url(".ru\u{FB06}up"), .userFile, .systemLocation)
        XCTAssertTrue(PathPolicy.isSame("/a/Stra\u{DF}e", "/a/STRASSE"))
        // It keeps accents apart, so "caf\u{E9}" is not "cafe".
        XCTAssertFalse(PathPolicy.isSame("/a/caf\u{E9}", "/a/cafe"))
    }

    func testAppleNamesAreRecognisedAfterFolding() throws {
        let item = try tree.makeDirectory("home/Library/Caches/COM.APPLE.Safari")
        assertRefused(item, .orphan, .appleItem)
        let folded = try tree.makeDirectory("home/Library/Caches/com.apple.\u{FB06}uff")
        assertRefused(folded, .orphan, .appleItem)
    }

    func testDecomposedNamesMatchComposedRules() throws {
        // "Tài liệu" with the accent as a separate combining mark.
        try tree.makeDirectory("home/Documents")
        let decomposed = home.url("Library/Caches/../../.ssh")
        assertRefused(decomposed, .userFile, .systemLocation)
        XCTAssertTrue(PathPolicy.isSame("/a/T\u{E0}i", "/a/Ta\u{300}i"))
    }

    // MARK: - Archives

    func testArchivesGoToTheTrash() throws {
        let archive = try tree.makeDirectory("home/Library/Developer/Xcode/Archives/2026-10-12/App.xcarchive")
        assertAllowed(archive, .buildArchive)
        assertRefused(archive, .regenerableCache, .outsideAllowedArea)
        XCTAssertEqual(RemovalPurpose.buildArchive.mode, .trash)
    }
}
