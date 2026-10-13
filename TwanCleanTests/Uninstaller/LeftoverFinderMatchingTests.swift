import XCTest
@testable import TwanClean

/// Whose file is whose: other apps' folders, shared company folders, copies of
/// the same app, and what is selected for the user.
final class LeftoverFinderMatchingTests: XCTestCase {
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

    private func install(_ relative: String, id: String, name: String) throws -> InstalledApp {
        try XCTUnwrap(InstalledAppIndex.app(at: try tree.makeAppBundle("home/Applications/\(relative).app",
                                                                        bundleIdentifier: id, name: name)))
    }

    private func find(_ app: InstalledApp, _ sensitivity: SearchSensitivity = .enhanced,
                      others: [InstalledApp] = []) throws -> LeftoverScan {
        try LeftoverFinder(home: home.home, policy: home.policy, systemFolders: [])
            .find(for: app, sensitivity: sensitivity, otherApps: others)
    }

    private func paths(_ scan: LeftoverScan) -> Set<String> {
        Set(scan.items.map { $0.url.path.replacingOccurrences(of: home.home.path + "/", with: "~/") })
    }

    private func item(_ scan: LeftoverScan, _ name: String) -> LeftoverItem? {
        scan.items.first { $0.name == name }
    }

    // MARK: - Other apps' folders

    func testAnotherAppsSupportFolderIsNotSearchedForTheNamesOfItsFiles() throws {
        let session = try install("Session", id: "com.loki-project.messenger-desktop", name: "Session")
        let claude = try install("Claude", id: "com.anthropic.claudefordesktop", name: "Claude")
        let code = try install("Visual Studio Code", id: "com.microsoft.VSCode", name: "Visual Studio Code")
        try tree.makeFile("home/Library/Application Support/Session/data", bytes: 4_096)
        try tree.makeFile("home/Library/Application Support/Claude/claude-code-sessions/log", bytes: 4_096)
        try tree.makeFile("home/Library/Application Support/Code/agentSessionData/state", bytes: 4_096)
        try tree.makeFile("home/Library/Application Support/Code/Session Storage/state", bytes: 4_096)

        for sensitivity in SearchSensitivity.allCases {
            let found = paths(try find(session, sensitivity, others: [session, claude, code]))
            XCTAssertEqual(found, ["~/Applications/Session.app", "~/Library/Application Support/Session"], "\(sensitivity)")
        }
    }

    func testFoldersOfAppsThatAreNotInstalledAreNotSearchedEither() throws {
        let session = try install("Session", id: "com.loki-project.messenger-desktop", name: "Session")
        try tree.makeFile("home/Library/Application Support/Claude/claude-code-sessions/log", bytes: 4_096)
        try tree.makeFile("home/Library/Application Support/Riot Client/Session Storage/state", bytes: 4_096)

        let found = paths(try find(session))

        XCTAssertEqual(found, ["~/Applications/Session.app"])
    }

    func testAFolderOfAnotherInstalledAppFromTheSameDeveloperIsLeftOut() throws {
        let editor = try install("Photo Editor", id: "com.example.photoeditor", name: "Photo Editor")
        let notes = try install("Example Notes", id: "com.example.notes", name: "Example Notes")
        try tree.makeFile("home/Library/Application Support/Example Notes/Photo Editor Data/blob", bytes: 4_096)
        try tree.makeFile("home/Library/Application Support/Example Inc/Photo Editor/settings", bytes: 4_096)

        let found = paths(try find(editor, others: [editor, notes]))

        XCTAssertFalse(found.contains { $0.contains("Example Notes") })
        XCTAssertTrue(found.contains("~/Library/Application Support/Example Inc/Photo Editor"))
    }

    func testFoldersNamedLikeABundleIdentifierAreNeverCompanyFolders() throws {
        let editor = try install("Photo Editor", id: "com.example.photoeditor", name: "Photo Editor")
        try tree.makeFile("home/Library/Application Support/com.example.launcher/Photo Editor Cache/blob", bytes: 4_096)

        XCTAssertFalse(paths(try find(editor)).contains { $0.contains("com.example.launcher") })
    }

    func testHelpersInsideTheAppAreNotRivalsForItsOwnFiles() throws {
        let editor = try install("Photo Editor", id: "com.example.photoeditor", name: "Photo Editor")
        let helper = try XCTUnwrap(InstalledAppIndex.read(
            try tree.makeAppBundle("home/Applications/Photo Editor.app/Contents/Library/LoginItems/Photo Editor Login Helper.app",
                                   bundleIdentifier: "com.example.photoeditor.loginhelper", name: "Photo Editor Login Helper"),
            readingTeam: false))
        try tree.makeFile("home/Library/Caches/Photo Editor Login Helper/blob", bytes: 4_096)

        let found = paths(try find(editor, others: [editor, helper]))

        XCTAssertTrue(found.contains("~/Library/Caches/Photo Editor Login Helper"))
    }

    // MARK: - What is selected

    func testOnlyExactAndIdentifierMatchesAreSelected() throws {
        let editor = try install("Photo Editor", id: "com.example.photoeditor", name: "Photo Editor")
        try tree.makeFile("home/Library/Application Support/Photo Editor/library.db", bytes: 4_096)
        try tree.makeFile("home/Library/Preferences/com.example.photoeditor.plist")
        try tree.makeFile("home/Library/Caches/com.example.photoeditor.helper/blob", bytes: 4_096)
        try tree.makeFile("home/Library/Caches/PhotoEditorBackups/blob", bytes: 4_096)
        try tree.makeFile("home/Library/Logs/Photo Editor Server Log/run", bytes: 4_096)

        let scan = try find(editor)

        XCTAssertEqual(item(scan, "Photo Editor")?.selectedByDefault, true)
        XCTAssertEqual(item(scan, "com.example.photoeditor.plist")?.selectedByDefault, true)
        XCTAssertEqual(item(scan, "com.example.photoeditor.helper")?.selectedByDefault, true)
        XCTAssertEqual(item(scan, "PhotoEditorBackups")?.selectedByDefault, false)
        XCTAssertEqual(item(scan, "Photo Editor Server Log")?.selectedByDefault, false)
    }

    func testNamesThatMerelyContainADigitStartedNameAreNotListed() throws {
        let app = try install("1Password", id: "com.agilebits.onepassword", name: "1Password")
        try tree.makeFile("home/Library/Application Support/1Password/data", bytes: 4_096)
        try tree.makeFile("home/Library/Caches/PasswordStore/blob", bytes: 4_096)
        try tree.makeFile("home/Library/Application Support/Passwords/blob", bytes: 4_096)

        XCTAssertEqual(paths(try find(app)), ["~/Applications/1Password.app", "~/Library/Application Support/1Password"])
    }

    func testOverrideTermsAreListedButNotSelected() throws {
        let zoom = try install("zoom.us", id: "us.zoom.xos", name: "zoom.us")
        try tree.makeFile("home/Library/Caches/ZoomOpener/blob", bytes: 4_096)
        try tree.makeFile("home/Library/Application Support/zoom.us/data", bytes: 4_096)

        let scan = try find(zoom)

        XCTAssertEqual(item(scan, "ZoomOpener")?.selectedByDefault, false)
        XCTAssertEqual(item(scan, "zoom.us")?.selectedByDefault, true)
    }

    func testQuickActionsAreOnlyListedWhenNamedExactlyAfterTheApp() throws {
        let editor = try install("Photo Editor", id: "com.example.photoeditor", name: "Photo Editor")
        try tree.makeFile("home/Library/Services/Photo Editor - ask.workflow/Contents/document.wflow")
        try tree.makeFile("home/Library/Services/send photo editor.workflow/Contents/document.wflow")
        try tree.makeFile("home/Library/Services/Photo Editor/Contents/document.wflow")

        let found = paths(try find(editor, .deep))

        XCTAssertEqual(found.filter { $0.contains("/Services/") }, ["~/Library/Services/Photo Editor"])
    }

    // MARK: - Two copies

    func testLeftoversAreNotSelectedWhileAnotherCopyStaysInstalled() throws {
        let first = try install("Photo Editor", id: "com.example.photoeditor", name: "Photo Editor")
        let second = try XCTUnwrap(InstalledAppIndex.app(at: try tree.makeAppBundle(
            "home/Applications/Old/Photo Editor.app", bundleIdentifier: "com.example.photoeditor", name: "Photo Editor")))
        try tree.makeFile("home/Library/Application Support/Photo Editor/library.db", bytes: 4_096)
        try tree.makeFile("home/Library/Preferences/com.example.photoeditor.plist")

        let scan = try find(first, others: [first, second])

        let bundle = try XCTUnwrap(scan.items.first { $0.group == .application })
        XCTAssertTrue(bundle.selectedByDefault)
        XCTAssertFalse(bundle.usedByAnotherCopy)
        let rest = scan.items.filter { $0.group != .application }
        XCTAssertEqual(rest.count, 2)
        XCTAssertTrue(rest.allSatisfy { !$0.selectedByDefault && $0.usedByAnotherCopy })
    }

    func testTheOtherCopyIsNotARivalForTheSharedFiles() throws {
        let first = try install("Photo Editor", id: "com.example.photoeditor", name: "Photo Editor")
        let second = try XCTUnwrap(InstalledAppIndex.app(at: try tree.makeAppBundle(
            "home/Applications/Old/Photo Editor.app", bundleIdentifier: "com.example.photoeditor", name: "Photo Editor")))
        try tree.makeFile("home/Library/Application Support/Photo Editor/library.db", bytes: 4_096)

        let scan = try find(first, others: [second])

        let leftover = try XCTUnwrap(item(scan, "Photo Editor"), "listed, not hidden as the other app's")
        XCTAssertFalse(leftover.mayBelongToAnotherApp)
    }

    func testASingleCopyKeepsSelectingItsFiles() throws {
        let editor = try install("Photo Editor", id: "com.example.photoeditor", name: "Photo Editor")
        try tree.makeFile("home/Library/Application Support/Photo Editor/library.db", bytes: 4_096)

        let leftover = try XCTUnwrap(item(try find(editor, others: [editor]), "Photo Editor"))

        XCTAssertTrue(leftover.selectedByDefault)
        XCTAssertFalse(leftover.usedByAnotherCopy)
    }

    // MARK: - Deep mode company folders

    func testACompanyFolderHoldingAnotherAppsDataIsFlaggedAndNotSelected() throws {
        let chrome = try install("Google Chrome", id: "com.google.Chrome", name: "Google Chrome")
        let drive = try install("Google Drive", id: "com.google.drivefs", name: "Google Drive")
        try tree.makeFile("home/Library/Application Support/Google/Google Drive/state", bytes: 4_096)
        try tree.makeFile("home/Library/Application Support/Google/Chrome/Default/Cookies", bytes: 4_096)

        let google = try XCTUnwrap(item(try find(chrome, .deep, others: [chrome, drive]), "Google"))

        XCTAssertEqual(google.tier, .developerName)
        XCTAssertTrue(google.mayBelongToAnotherApp)
        XCTAssertFalse(google.selectedByDefault)
    }

    func testAFolderAnotherAppOwnsThroughItsOverrideCountsAsItsData() throws {
        let chrome = try install("Google Chrome", id: "com.google.Chrome", name: "Google Chrome")
        let drive = try install("Google Drive", id: "com.google.drivefs", name: "Google Drive")
        try tree.makeFile("home/Library/Application Support/Google/Chrome/Default/Cookies", bytes: 4_096)

        let google = try XCTUnwrap(item(try find(drive, .deep, others: [chrome, drive]), "Google"))

        XCTAssertTrue(google.mayBelongToAnotherApp)
    }

    func testACompanyFolderHoldingOnlyTheAppsOwnDataIsNotFlagged() throws {
        let chrome = try install("Google Chrome", id: "com.google.Chrome", name: "Google Chrome")
        try tree.makeFile("home/Library/Application Support/Google/Chrome/Default/Cookies", bytes: 4_096)

        let google = try XCTUnwrap(item(try find(chrome, .deep, others: [chrome]), "Google"))

        XCTAssertFalse(google.mayBelongToAnotherApp)
        XCTAssertFalse(google.selectedByDefault, "found through the developer, never selected")
    }

    // MARK: - Override folders

    func testChromeFindsItsDataFoldersAndAChromeBetaDoesNot() throws {
        let chrome = try install("Google Chrome", id: "com.google.Chrome", name: "Google Chrome")
        let beta = try install("Google Chrome Beta", id: "com.google.Chrome.beta", name: "Google Chrome Beta")
        try tree.makeFile("home/Library/Application Support/Google/Chrome/Default/Cookies", bytes: 4_096)
        try tree.makeFile("home/Library/Caches/Google/Chrome/Default/Cache/data", bytes: 4_096)

        let stable = paths(try find(chrome, others: [chrome, beta]))
        let betaFound = paths(try find(beta, others: [chrome, beta]))

        XCTAssertTrue(stable.contains("~/Library/Application Support/Google/Chrome"))
        XCTAssertTrue(stable.contains("~/Library/Caches/Google/Chrome"))
        XCTAssertFalse(betaFound.contains { $0.hasSuffix("Google/Chrome") })
    }

    // MARK: - Cancellation

    func testACancelledScanStops() async throws {
        let editor = try install("Photo Editor", id: "com.example.photoeditor", name: "Photo Editor")
        try tree.makeFile("home/Library/Application Support/Photo Editor/library.db", bytes: 4_096)
        let finder = LeftoverFinder(home: home.home, policy: home.policy, systemFolders: [])

        let task = Task { () -> Bool in
            await runDetached {
                // Hold the scan back until the cancellation has reached it.
                let deadline = Date().addingTimeInterval(5)
                while !Task.isCancelled, Date() < deadline { usleep(1_000) }
                do {
                    _ = try finder.find(for: editor, sensitivity: .enhanced)
                    return false
                } catch is CancellationError {
                    return true
                } catch {
                    return false
                }
            }
        }
        task.cancel()

        let stopped = await task.value
        XCTAssertTrue(stopped)
    }
}
