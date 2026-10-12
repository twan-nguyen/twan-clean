import XCTest
@testable import TwanClean

final class PrivilegedRemoverTests: XCTestCase {
    func testStagingFileListsPathsSeparatedByNUL() throws {
        let paths = ["/Library/Caches/a b", "/Library/Caches/it's \"quoted\"", "/Library/Caches/$(reboot)\nnext"]
        let file = try PrivilegedRemover.stage(paths: paths)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let data = try Data(contentsOf: file)
        let decoded = data.split(separator: 0, omittingEmptySubsequences: true).map { String(decoding: $0, as: UTF8.self) }
        XCTAssertEqual(decoded, paths)
        XCTAssertEqual(data.last, 0)

        let fileMode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int)
        let folderMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: file.deletingLastPathComponent().path)[.posixPermissions] as? Int)
        XCTAssertEqual(fileMode & 0o777, 0o600)
        XCTAssertEqual(folderMode & 0o777, 0o700)
    }

    func testStagingRejectsNUL() {
        XCTAssertThrowsError(try PrivilegedRemover.stage(paths: ["/tmp/a\u{0}b"]))
    }

    func testScriptOnlyReferencesTheStagingFile() throws {
        let file = try PrivilegedRemover.stage(paths: ["/Library/Caches/it's \"evil\"; rm -rf ~"])
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let script = try PrivilegedRemover.script(stagingFile: file, prompt: "Remove items")

        XCTAssertTrue(script.hasPrefix("do shell script \"/usr/bin/xargs -0 /bin/rm -rf -- < \" & quoted form of \""))
        XCTAssertTrue(script.contains(file.path))
        XCTAssertFalse(script.contains("evil"))
        XCTAssertTrue(script.hasSuffix("with administrator privileges"))
    }

    func testScriptRefusesUnusualStagingPath() {
        let odd = URL(fileURLWithPath: "/tmp/it's here/paths")
        XCTAssertThrowsError(try PrivilegedRemover.script(stagingFile: odd, prompt: "x"))
    }

    func testPromptIsEscapedAsAppleScriptString() {
        XCTAssertEqual(PrivilegedRemover.appleScriptLiteral(#"Say "hi" \ bye"#), #""Say \"hi\" \\ bye""#)
    }

    func testCancelledAuthorizationIsRecognised() {
        XCTAssertTrue(AdministratorError(output: "execution error: User canceled. (-128)").wasCancelled)
        XCTAssertFalse(AdministratorError(output: "rm: Operation not permitted").wasCancelled)
    }
}
