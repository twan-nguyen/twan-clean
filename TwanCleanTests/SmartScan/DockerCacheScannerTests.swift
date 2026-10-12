import XCTest
@testable import TwanClean

final class DockerCacheScannerTests: XCTestCase {
    func testParsesDockerSizes() {
        XCTAssertEqual(DockerCacheScanner.parseSize("512B"), 512)
        XCTAssertEqual(DockerCacheScanner.parseSize("12.5kB"), 12_500)
        XCTAssertEqual(DockerCacheScanner.parseSize("1.2GB"), 1_200_000_000)
        XCTAssertNil(DockerCacheScanner.parseSize("lots"))
    }

    func testSumsReclaimableLines() {
        let output = "1.2GB (45%)\n0B (0%)\n300MB (12%)"
        XCTAssertEqual(DockerCacheScanner.reclaimableBytes(output), 1_500_000_000)
    }

    func testNoParsableLinesGivesNil() {
        XCTAssertNil(DockerCacheScanner.reclaimableBytes("Cannot connect to the Docker daemon"))
    }
}
