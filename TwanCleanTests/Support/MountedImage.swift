import Foundation
import XCTest

/// A small disk image attached at a folder of a test tree, so a test can meet
/// a real mount point. Attaching needs no administrator rights. Call `detach`
/// (in a `defer`) before the tree is removed.
final class MountedImage {
    let mountPoint: URL
    private let image: URL

    /// Throws `XCTSkip` when the image cannot be created or attached, e.g. in
    /// a sandbox that forbids `hdiutil`.
    init(at mountPoint: URL, imageFolder: URL) throws {
        self.mountPoint = mountPoint
        image = imageFolder.appendingPathComponent("\(UUID().uuidString).dmg")
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        guard Self.hdiutil(["create", "-size", "4m", "-fs", "APFS", "-volname", "TwanCleanTest", image.path]),
              Self.hdiutil(["attach", image.path, "-mountpoint", mountPoint.path, "-nobrowse", "-noverify", "-noautoopen"])
        else { throw XCTSkip("hdiutil could not attach a test disk image") }
    }

    func detach() {
        _ = Self.hdiutil(["detach", mountPoint.path, "-force"])
        try? FileManager.default.removeItem(at: image)
    }

    private static func hdiutil(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
