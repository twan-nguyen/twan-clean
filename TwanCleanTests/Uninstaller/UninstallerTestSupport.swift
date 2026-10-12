import Foundation
@testable import TwanClean

func makeApp(name: String = "Photo Editor", bundleIdentifier: String = "com.example.photoeditor",
             team: String? = "ABCDE12345") -> InstalledApp {
    InstalledApp(url: URL(fileURLWithPath: "/Applications/\(name).app"), bundleIdentifier: bundleIdentifier,
                 name: name, version: "1.0", identity: FileIdentity(device: 1, inode: 1), teamIdentifier: team)
}

extension TemporaryTree {
    /// A minimal app bundle with an Info.plist.
    @discardableResult
    func makeAppBundle(_ relative: String, bundleIdentifier: String, name: String? = nil) throws -> URL {
        let app = try makeDirectory(relative)
        try makeDirectory("\(relative)/Contents/MacOS")
        var info: [String: Any] = ["CFBundleIdentifier": bundleIdentifier, "CFBundleShortVersionString": "2.1"]
        if let name { info["CFBundleName"] = name }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        try makeFile("\(relative)/Contents/MacOS/binary", bytes: 4_096)
        return app
    }
}
