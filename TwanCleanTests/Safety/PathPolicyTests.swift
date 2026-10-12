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

    private func assertRefused(_ url: URL, _ purpose: RemovalPurpose, _ reason: RefusalReason,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(decision(url, purpose), .refused(reason), url.path, file: file, line: line)
    }

    // MARK: - Allowed

    func testCacheItemIsAllowedForRegenerableCache() throws {
        let item = try tree.makeFile("home/Library/Caches/com.example.app/data.bin")
        XCTAssertEqual(decision(item, .regenerableCache), .allowed(item))
    }

    func testUserFileInDownloadsIsAllowed() throws {
        let item = try tree.makeFile("home/Downloads/movie.mov")
        XCTAssertEqual(decision(item, .userFile), .allowed(item))
    }

    func testTrashChildIsAllowedForTrashContents() throws {
        let item = try tree.makeFile("home/.Trash/old.zip")
        XCTAssertEqual(decision(item, .trashContents), .allowed(item))
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
        assertRefused(home.url("Library/Caches"), .regenerableCache, .outsideAllowedArea)
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
        XCTAssertEqual(decision(URL(fileURLWithPath: "/Applications/Example.app"), .appBundle),
                       .allowed(URL(fileURLWithPath: "/Applications/Example.app")))
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
        XCTAssertEqual(decision(link, .regenerableCache), .allowed(link))
    }

    func testMissingParentIsUnresolvable() {
        assertRefused(home.url("Library/Caches/missing/child"), .regenerableCache, .unresolvable)
    }

    func testNonFileURLIsRefused() throws {
        assertRefused(try XCTUnwrap(URL(string: "https://example.com/x")), .userFile, .notAFileURL)
    }
}
