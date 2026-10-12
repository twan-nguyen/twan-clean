import XCTest
@testable import TwanClean

final class CirclePackerTests: XCTestCase {
    private let canvas = CGSize(width: 600, height: 400)

    func testEmptyInputGivesNoFrames() {
        XCTAssertTrue(CirclePacker.pack([], in: canvas).isEmpty)
    }

    func testSingleCircleIsCentredAndFits() throws {
        let frame = try XCTUnwrap(CirclePacker.pack([100], in: canvas).first)
        XCTAssertEqual(frame.midX, canvas.width / 2, accuracy: 0.5)
        XCTAssertEqual(frame.midY, canvas.height / 2, accuracy: 0.5)
        XCTAssertLessThanOrEqual(frame.height, canvas.height)
    }

    func testLayoutIsDeterministic() {
        let sizes: [Int64] = [900, 500, 300, 120, 80, 40, 10]
        XCTAssertEqual(CirclePacker.pack(sizes, in: canvas), CirclePacker.pack(sizes, in: canvas))
    }

    func testCirclesDoNotOverlapAndStayInside() {
        let sizes: [Int64] = (1...25).map { Int64(1_000 / $0) }
        let frames = CirclePacker.pack(sizes, in: canvas)
        XCTAssertEqual(frames.count, sizes.count)
        let bounds = CGRect(origin: .zero, size: canvas)
        for (index, frame) in frames.enumerated() {
            XCTAssertTrue(bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(index) outside")
            for other in frames[(index + 1)...] {
                let distance = hypot(frame.midX - other.midX, frame.midY - other.midY)
                XCTAssertGreaterThanOrEqual(distance + 0.01, frame.width / 2 + other.width / 2)
            }
        }
    }

    func testAreaFollowsSize() {
        let frames = CirclePacker.pack([400, 100], in: canvas)
        XCTAssertEqual(frames[0].width / frames[1].width, 2, accuracy: 0.01)
    }

    func testTinyAndZeroSizesStayVisible() {
        let frames = CirclePacker.pack([1_000_000, 0, 1], in: canvas)
        XCTAssertTrue(frames.dropFirst().allSatisfy { $0.width >= frames[0].width * CirclePacker.minimumRadiusRatio - 0.01 })
    }
}
