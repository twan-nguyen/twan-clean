import XCTest
@testable import TwanClean

final class CommandRunnerTrustTests: XCTestCase {
    private var tree: TemporaryTree!

    override func setUpWithError() throws {
        tree = try TemporaryTree()
    }

    override func tearDown() {
        tree = nil
    }

    private func makeTool(_ relative: String, mode: mode_t) throws -> URL {
        let tool = try tree.makeFile(relative)
        try "#!/bin/sh\necho ran\n".write(to: tool, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(tool.path, mode), 0)
        return tool
    }

    private func runner(_ folder: String) -> CommandRunner {
        CommandRunner(searchPaths: [tree.url(folder).path], timeout: 5)
    }

    func testToolOwnedByTheUserAndNotSharedIsRun() async throws {
        _ = try makeTool("bin/tool", mode: 0o755)
        let output = await runner("bin").output(of: "tool", [])
        XCTAssertEqual(output, "ran")
    }

    func testToolWritableByGroupOrOthersIsNotRun() async throws {
        _ = try makeTool("group/tool", mode: 0o775)
        _ = try makeTool("others/tool", mode: 0o757)
        let groupOutput = await runner("group").output(of: "tool", [])
        let othersOutput = await runner("others").output(of: "tool", [])
        XCTAssertNil(groupOutput)
        XCTAssertNil(othersOutput)
        XCTAssertNil(runner("group").locate("tool"))
    }

    func testSearchContinuesPastAnUntrustedCopy() async throws {
        _ = try makeTool("first/tool", mode: 0o777)
        _ = try makeTool("second/tool", mode: 0o755)
        let both = CommandRunner(searchPaths: [tree.url("first").path, tree.url("second").path], timeout: 5)

        XCTAssertEqual(both.locate("tool")?.path, tree.url("second/tool").path)
        let output = await both.output(of: "tool", [])
        XCTAssertEqual(output, "ran")
    }

    func testSymlinkToAnUntrustedTargetIsNotRun() async throws {
        let target = try makeTool("real/tool", mode: 0o775)
        try tree.makeSymlink("bin/tool", to: target)

        XCTAssertNil(runner("bin").locate("tool"))
        let output = await runner("bin").output(of: "tool", [])
        XCTAssertNil(output)
    }

    func testSymlinkToATrustedTargetIsRun() async throws {
        let target = try makeTool("real/tool", mode: 0o755)
        try tree.makeSymlink("bin/tool", to: target)

        let output = await runner("bin").output(of: "tool", [])
        XCTAssertEqual(output, "ran")
    }

    func testUrlOverloadAppliesTheSameCheck() async throws {
        let unsafe = try makeTool("direct/tool", mode: 0o777)
        let output = await runner("direct").output(of: unsafe, [])
        XCTAssertNil(output)
    }

    func testToolOwnedBySomeoneElseIsNotTrusted() throws {
        let tool = try makeTool("bin/tool", mode: 0o755)
        XCTAssertTrue(CommandRunner.isTrusted(tool.path))
        // Owned by this user, so another user would not trust it.
        XCTAssertFalse(CommandRunner.isTrusted(tool.path, user: getuid() &+ 1))
    }

    func testSystemToolsAreTrusted() {
        for path in ["/bin/echo", "/usr/bin/env", "/bin/sh"] {
            XCTAssertTrue(CommandRunner.isTrusted(path), path)
        }
    }

    func testMissingToolIsNotTrusted() {
        XCTAssertFalse(CommandRunner.isTrusted(tree.url("nothing").path))
    }
}
