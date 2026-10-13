import XCTest
@testable import TwanClean

final class InstalledAppIndexTests: XCTestCase {
    private var tree: TemporaryTree!

    override func setUpWithError() throws {
        tree = try TemporaryTree()
    }

    override func tearDown() {
        tree = nil
    }

    func testListsAppsWithNamesAndVersions() throws {
        try tree.makeAppBundle("Applications/Editor.app", bundleIdentifier: "com.example.editor", name: "Editor")
        try tree.makeAppBundle("Applications/Utilities/Tool.app", bundleIdentifier: "com.example.tool")

        let apps = InstalledAppIndex(roots: [tree.url("Applications")]).apps()

        XCTAssertEqual(apps.map(\.name), ["Editor", "Tool"])
        XCTAssertEqual(apps.first?.version, "2.1")
        XCTAssertEqual(apps.first?.url.path, tree.url("Applications/Editor.app").path)
    }

    func testTwoCopiesWithTheSameIdentifierAreBothListed() throws {
        try tree.makeAppBundle("Applications/Editor.app", bundleIdentifier: "com.example.editor", name: "Editor")
        try tree.makeAppBundle("User/Editor Copy.app", bundleIdentifier: "com.example.editor")

        let apps = InstalledAppIndex(roots: [tree.url("Applications"), tree.url("User")]).apps()

        XCTAssertEqual(apps.map(\.name), ["Editor", "Editor Copy"])
    }

    func testOverlappingRootsListAnAppOnce() throws {
        try tree.makeAppBundle("Applications/Utilities/Tool.app", bundleIdentifier: "com.example.tool")

        let apps = InstalledAppIndex(roots: [tree.url("Applications"), tree.url("Applications/Utilities")]).apps()

        XCTAssertEqual(apps.count, 1)
    }

    func testFindsAppsInSubfoldersOfTheApplicationsFolder() throws {
        try tree.makeAppBundle("Applications/Setapp/Paste.app", bundleIdentifier: "com.setapp.paste")
        try tree.makeAppBundle("Applications/Utilities/Tool.app", bundleIdentifier: "com.example.tool")
        try tree.makeAppBundle("Applications/A/B/C/D/TooDeep.app", bundleIdentifier: "com.example.toodeep")

        let apps = InstalledAppIndex(roots: [tree.url("Applications")]).apps()

        XCTAssertEqual(Set(apps.map(\.bundleIdentifier)), ["com.setapp.paste", "com.example.tool"])
    }

    func testAppsReachedThroughASymbolicLinkAreNotListed() throws {
        let real = try tree.makeAppBundle("Shared/Riot Client.app", bundleIdentifier: "com.example.riot")
        try tree.makeSymlink("Applications/Client Riot.app", to: real)
        try tree.makeAppBundle("Applications/Editor.app", bundleIdentifier: "com.example.editor")

        let apps = InstalledAppIndex(roots: [tree.url("Applications")]).apps()

        XCTAssertEqual(apps.map(\.bundleIdentifier), ["com.example.editor"])
        XCTAssertNil(InstalledAppIndex.app(at: tree.url("Applications/Client Riot.app")))
        XCTAssertNotNil(InstalledAppIndex.app(at: real))
    }

    func testCatalogCountsAppsOutsideTheRootsAsInstalledButNeverListsThem() throws {
        try tree.makeAppBundle("Applications/Editor.app", bundleIdentifier: "com.example.editor")
        let shared = try tree.makeAppBundle("Shared/Updater.app", bundleIdentifier: "com.example.updater")
        let trashed = try tree.makeAppBundle("home/.Trash/Gone.app", bundleIdentifier: "com.example.gone")
        let index = InstalledAppIndex(roots: [tree.url("Applications")], additionalApplications: { [shared, trashed] })

        let catalog = index.catalog()

        XCTAssertEqual(index.apps().map(\.bundleIdentifier), ["com.example.editor"])
        XCTAssertEqual(catalog.listed.map(\.bundleIdentifier), ["com.example.editor"])
        XCTAssertEqual(catalog.related.map(\.bundleIdentifier), ["com.example.updater"])
        XCTAssertEqual(Set(catalog.everyApp.map(\.bundleIdentifier)), ["com.example.editor", "com.example.updater"])
    }

    func testCatalogFindsHelperAppsAndIdentifiersInsideApps() throws {
        try tree.makeAppBundle("Applications/Suite.app", bundleIdentifier: "com.example.suite")
        try tree.makeAppBundle("Applications/Suite.app/Contents/Library/LoginItems/Launcher.app",
                               bundleIdentifier: "com.example.suite.launcher")
        try tree.makeAppBundle("Applications/Suite.app/Contents/LoL/LeagueClient.app",
                               bundleIdentifier: "com.example.suite.client")
        let agent = try PropertyListSerialization.data(fromPropertyList: ["Label": "com.example.suite.agent"],
                                                       format: .xml, options: 0)
        try tree.makeDirectory("Applications/Suite.app/Contents/Library/LaunchAgents")
        try agent.write(to: tree.url("Applications/Suite.app/Contents/Library/LaunchAgents/agent.plist"))
        let daemon = try PropertyListSerialization.data(fromPropertyList: ["Label": "com.example.suite.daemon"],
                                                        format: .xml, options: 0)
        try tree.makeDirectory("Applications/Suite.app/Contents/Library/LaunchDaemons")
        try daemon.write(to: tree.url("Applications/Suite.app/Contents/Library/LaunchDaemons/daemon.plist"))
        try tree.makeFile("Applications/Suite.app/Contents/Library/LaunchServices/com.example.suite.tool")

        let catalog = InstalledAppIndex(roots: [tree.url("Applications")]).catalog()

        XCTAssertEqual(catalog.listed.map(\.bundleIdentifier), ["com.example.suite"])
        XCTAssertEqual(Set(catalog.nested.map(\.bundleIdentifier)), ["com.example.suite.launcher", "com.example.suite.client"])
        XCTAssertEqual(catalog.extraIdentifiers,
                       ["com.example.suite.agent", "com.example.suite.daemon", "com.example.suite.tool"])
    }

    func testCatalogIsIncompleteWhenNothingIsInstalledOrAFolderCannotBeRead() throws {
        XCTAssertFalse(InstalledAppIndex(roots: [try tree.makeDirectory("Empty")]).catalog().isComplete)

        try tree.makeAppBundle("Locked/Editor.app", bundleIdentifier: "com.example.editor")
        try tree.makeAppBundle("Open/Tool.app", bundleIdentifier: "com.example.tool")
        chmod(tree.url("Locked").path, 0o000)
        let catalog = InstalledAppIndex(roots: [tree.url("Locked"), tree.url("Open")]).catalog()

        XCTAssertEqual(catalog.unreadableRoots.map(\.lastPathComponent), ["Locked"])
        XCTAssertFalse(catalog.isComplete)
        XCTAssertEqual(catalog.listed.map(\.bundleIdentifier), ["com.example.tool"])
    }

    func testCatalogIsCompleteWithAnAppAndReadableRoots() throws {
        try tree.makeAppBundle("Applications/Editor.app", bundleIdentifier: "com.example.editor")
        XCTAssertTrue(InstalledAppIndex(roots: [tree.url("Applications"), tree.url("NoSuchFolder")]).catalog().isComplete)
    }

    func testSkipsProtectedAppsAndAppsInsideApps() throws {
        try tree.makeAppBundle("Applications/Safari.app", bundleIdentifier: "com.apple.Safari")
        try tree.makeAppBundle("Applications/Suite.app", bundleIdentifier: "com.example.suite")
        try tree.makeAppBundle("Applications/Suite.app/Contents/Helpers/Helper.app", bundleIdentifier: "com.example.helper")

        let apps = InstalledAppIndex(roots: [tree.url("Applications")]).apps()

        XCTAssertEqual(apps.map(\.bundleIdentifier), ["com.example.suite"])
    }

    func testIgnoresBundlesWithoutAnIdentifier() throws {
        try tree.makeDirectory("Applications/Broken.app/Contents")
        XCTAssertTrue(InstalledAppIndex(roots: [tree.url("Applications")]).apps().isEmpty)
    }

    func testSizeCacheReusesMeasurementsUntilTheAppChanges() async throws {
        let bundle = try tree.makeAppBundle("Applications/Editor.app", bundleIdentifier: "com.example.editor")
        let app = try XCTUnwrap(InstalledAppIndex.app(at: bundle))
        let cache = AppSizeCache(file: tree.url("sizes.json"))

        let first = try await cache.size(of: app)
        try tree.makeFile("Applications/Editor.app/Contents/MacOS/extra", bytes: 100_000)
        let cached = try await cache.size(of: app)

        XCTAssertGreaterThan(first, 0)
        XCTAssertEqual(cached, first)
        await cache.save()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tree.url("sizes.json").path))
    }
}
