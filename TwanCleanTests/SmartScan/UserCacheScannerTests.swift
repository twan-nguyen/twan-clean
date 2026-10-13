import XCTest
@testable import TwanClean

final class UserCacheScannerTests: XCTestCase {
    private var tree: TemporaryTree!
    private var home: FakeHome!

    override func setUpWithError() throws {
        tree = try TemporaryTree()
        home = try FakeHome(tree: tree)
        try tree.makeFile("home/Library/Caches/com.example.editor/cache.db", bytes: 8_192)
        try tree.makeFile("home/Library/Caches/com.example.player/blob", bytes: 8_192)
        try tree.makeFile("home/Library/Caches/com.apple.Safari/cache.db", bytes: 8_192)
        try tree.makeFile("home/Library/Caches/Homebrew/downloads/x.tar.gz", bytes: 8_192)
        try tree.makeFile("home/.cache/pip/wheel", bytes: 8_192)
        try tree.makeDirectory("home/Library/Caches/com.example.empty")
    }

    override func tearDown() {
        home = nil
        tree = nil
    }

    private func scan(running: Set<String> = [], apps: [RunningApp] = []) async throws -> [String: CleanableItem] {
        let result = try await UserCacheScanner().scan(home.scanContext(running: running, runningApps: apps))
        return Dictionary(uniqueKeysWithValues: result.items.map { ($0.name, $0) })
    }

    func testFindsCacheFoldersDynamically() async throws {
        let items = try await scan()
        XCTAssertNotNil(items["com.example.editor"])
        XCTAssertNotNil(items["pip"])
        XCTAssertEqual(items["com.example.editor"]?.purpose, .regenerableCache)
        XCTAssertEqual(items["com.example.editor"]?.selectedByDefault, true)
    }

    func testLeavesClaimedAndEmptyFoldersOut() async throws {
        let items = try await scan()
        XCTAssertNil(items["Homebrew"])
        XCTAssertNil(items["com.example.empty"])
    }

    func testDoesNotPreselectCachesOfRunningAppsOrMacOS() async throws {
        let items = try await scan(running: ["com.example.Player"])
        XCTAssertEqual(items["com.example.player"]?.selectedByDefault, false)
        XCTAssertTrue(items["com.example.player"]?.notes.contains(.appIsRunning) ?? false)
        XCTAssertEqual(items["com.apple.Safari"]?.selectedByDefault, false)
    }

    func testSizesAreAllocatedBytes() async throws {
        let items = try await scan()
        XCTAssertGreaterThanOrEqual(items["com.example.editor"]?.bytes ?? 0, 8_192)
    }

    func testFilesHardLinkedOutsideTheCacheAreNotCountedAsFreed() async throws {
        let shared = try tree.makeFile("home/Library/Caches/com.example.store/blob", bytes: 65_536)
        try FileManager.default.linkItem(at: shared, to: tree.url("home/project-copy"))
        let items = try await scan()
        XCTAssertEqual(items["com.example.store"]?.bytes, 0)
    }

    // MARK: - ~/.cache

    func testOnlyKnownRegenerableDotCacheFoldersArePreselected() async throws {
        try tree.makeFile("home/.cache/uv/archive", bytes: 8_192)
        try tree.makeFile("home/.cache/lm-studio/conversations/chat.json", bytes: 8_192)
        try tree.makeFile("home/.cache/some-tool/state.db", bytes: 8_192)
        let items = try await scan()

        XCTAssertEqual(items["pip"]?.selectedByDefault, true)
        XCTAssertEqual(items["pip"]?.purpose, .regenerableCache)
        XCTAssertEqual(items["uv"]?.selectedByDefault, true)

        for name in ["lm-studio", "some-tool"] {
            let item = try XCTUnwrap(items[name], name)
            XCTAssertFalse(item.selectedByDefault, name)
            // Unknown data is never deleted outright if the user ticks it.
            XCTAssertEqual(item.purpose, .userFile, name)
        }
        XCTAssertTrue(items["lm-studio"]?.notes.contains(.personalData) ?? false)
        XCTAssertTrue(items["some-tool"]?.notes.contains(.mayBeNeeded) ?? false)
    }

    func testHuggingFaceIsListedForTheTrashNotDeletedOutright() async throws {
        try tree.makeFile("home/.cache/huggingface/token", bytes: 64)
        try tree.makeFile("home/.cache/huggingface/hub/model.bin", bytes: 8_192)
        let items = try await scan()
        let item = try XCTUnwrap(items["huggingface"])
        XCTAssertFalse(item.selectedByDefault)
        XCTAssertEqual(item.purpose, .userFile)
        XCTAssertEqual(item.purpose.mode, .trash)
        XCTAssertTrue(item.notes.contains(.personalData))
    }

    func testPoetryEnvironmentsInDotCacheAreNotPreselected() async throws {
        try tree.makeFile("home/.cache/pypoetry/virtualenvs/app/bin/python", bytes: 8_192)
        let items = try await scan()
        let item = try XCTUnwrap(items["pypoetry"])
        XCTAssertFalse(item.selectedByDefault)
    }

    // MARK: - Library caches

    func testIDEHistoryAndToolEnvironmentsAreNeverPreselected() async throws {
        try tree.makeFile("home/Library/Caches/JetBrains/IntelliJIdea2025.1/LocalHistory/changes.storageData", bytes: 8_192)
        try tree.makeFile("home/Library/Caches/pypoetry/virtualenvs/app/bin/python", bytes: 8_192)
        try tree.makeFile("home/Library/Caches/Google/AndroidStudio2025.1/LocalHistory/changes", bytes: 8_192)
        try tree.makeFile("home/Library/Caches/Google/Chrome/Default/Cache/data_0", bytes: 8_192)
        let items = try await scan()

        XCTAssertEqual(items["JetBrains"]?.selectedByDefault, false)
        XCTAssertTrue(items["JetBrains"]?.notes.contains(.personalData) ?? false)
        XCTAssertEqual(items["pypoetry"]?.selectedByDefault, false)
        XCTAssertEqual(items["AndroidStudio2025.1"]?.selectedByDefault, false)
        XCTAssertTrue(items["AndroidStudio2025.1"]?.notes.contains(.personalData) ?? false)
        // Chrome's own cache is still an ordinary cache.
        XCTAssertEqual(items["Chrome"]?.selectedByDefault, true)
        XCTAssertNil(items["Google"])
    }

    func testCacheOfARunningAppIsFoundByVendorAndNameNotOnlyByBundleID() async throws {
        try tree.makeFile("home/Library/Caches/Google/Chrome/Default/Cache/data_0", bytes: 8_192)
        try tree.makeFile("home/Library/Caches/Firefox/profile/cache2", bytes: 8_192)
        try tree.makeFile("home/Library/Caches/JetBrains/IntelliJIdea2025.1/index", bytes: 8_192)
        let apps = [
            RunningApp(bundleID: "com.google.Chrome", name: "Google Chrome", executableName: "Google Chrome"),
            RunningApp(bundleID: "org.mozilla.firefox", name: "Firefox", executableName: "firefox"),
            RunningApp(bundleID: "com.jetbrains.intellij", name: "IntelliJ IDEA", executableName: "idea"),
        ]
        let items = try await scan(apps: apps)

        for name in ["Chrome", "Firefox", "JetBrains"] {
            let item = try XCTUnwrap(items[name], name)
            XCTAssertTrue(item.notes.contains(.appIsRunning), name)
            XCTAssertFalse(item.selectedByDefault, name)
        }
        // Without the apps running, Chrome and Firefox are ordinary caches.
        let idle = try await scan()
        XCTAssertEqual(idle["Chrome"]?.selectedByDefault, true)
        XCTAssertEqual(idle["Firefox"]?.selectedByDefault, true)
    }

    func testFolderPrefixedByARunningBundleIDBelongsToIt() async throws {
        try tree.makeFile("home/Library/Caches/com.example.player.helper/blob", bytes: 8_192)
        let items = try await scan(running: ["com.example.Player"])
        XCTAssertEqual(items["com.example.player.helper"]?.selectedByDefault, false)
    }
}

final class RunningAppIndexTests: XCTestCase {
    func testMatchesBundleIDNameExecutableAndVendorIgnoringCase() {
        let index = RunningAppIndex(apps: [
            RunningApp(bundleID: "com.google.Chrome", name: "Google Chrome", executableName: "chrome-bin")
        ])
        XCTAssertTrue(index.owns(folderNamed: "com.GOOGLE.chrome"))
        XCTAssertTrue(index.owns(folderNamed: "google chrome"))
        XCTAssertTrue(index.owns(folderNamed: "Chrome-Bin"))
        XCTAssertTrue(index.owns(folderNamed: "Google"))
        XCTAssertTrue(index.owns(folderNamed: "com.google.Chrome.savedState"))
        XCTAssertFalse(index.owns(folderNamed: "Mozilla"))
    }

    func testApplesVendorNameIsNotAMatch() {
        let index = RunningAppIndex(bundleIDs: ["com.apple.Safari"])
        XCTAssertFalse(index.owns(folderNamed: "Apple"))
        XCTAssertTrue(index.owns(folderNamed: "com.apple.Safari"))
    }

    func testOwnersNameAppsTheFolderIsNotNamedAfter() {
        let index = RunningAppIndex(bundleIDs: ["com.docker.docker"])
        XCTAssertTrue(index.owns(folderNamed: "tmp", owners: ["com.docker.docker"]))
        XCTAssertFalse(index.owns(folderNamed: "tmp", owners: ["com.example.other"]))
    }

    func testVeryShortNamesAreIgnored() {
        let index = RunningAppIndex(apps: [RunningApp(name: "Go", executableName: "go")])
        XCTAssertFalse(index.owns(folderNamed: "go"))
    }
}
