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

    func testListsAppsWithNamesVersionsAndNoDuplicates() throws {
        try tree.makeAppBundle("Applications/Editor.app", bundleIdentifier: "com.example.editor", name: "Editor")
        try tree.makeAppBundle("Applications/Utilities/Tool.app", bundleIdentifier: "com.example.tool")
        try tree.makeAppBundle("User/Editor Copy.app", bundleIdentifier: "com.example.editor")

        let apps = InstalledAppIndex(roots: [tree.url("Applications"), tree.url("User")]).apps()

        XCTAssertEqual(apps.map(\.name), ["Editor", "Tool"])
        XCTAssertEqual(apps.first?.version, "2.1")
        XCTAssertEqual(apps.first?.url.path, tree.url("Applications/Editor.app").path)
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
