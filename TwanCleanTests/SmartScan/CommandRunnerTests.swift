import XCTest
@testable import TwanClean

final class CommandRunnerTests: XCTestCase {
    private let runner = CommandRunner(searchPaths: ["/bin", "/usr/bin"], timeout: 1)

    func testReturnsTrimmedOutput() async {
        let output = await runner.output(of: "echo", ["  hello  "])
        XCTAssertEqual(output, "hello")
    }

    func testMissingToolGivesNil() async {
        let output = await runner.output(of: "definitely-not-a-tool", [])
        XCTAssertNil(output)
    }

    func testFailingToolGivesNil() async {
        let output = await runner.output(of: "false", [])
        XCTAssertNil(output)
    }

    func testSlowToolIsStoppedAtTheTimeout() async {
        let started = Date()
        let output = await runner.output(of: "sleep", ["5"])
        XCTAssertNil(output)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testArgumentsAreNotInterpretedByAShell() async {
        let output = await runner.output(of: "echo", ["$(whoami); rm -rf /"])
        XCTAssertEqual(output, "$(whoami); rm -rf /")
    }

    func testHomebrewVariablesAreNotPassedOn() async {
        setenv("HOMEBREW_CACHE", "/tmp/elsewhere", 1)
        defer { unsetenv("HOMEBREW_CACHE") }
        let output = await runner.output(of: "env", [])
        XCTAssertFalse(output?.contains("HOMEBREW_CACHE") ?? true)
    }
}
