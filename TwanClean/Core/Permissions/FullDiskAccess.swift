import AppKit

/// Detects and requests Full Disk Access, which macOS needs before any app can
/// read Mail, Safari or other protected Library folders.
enum FullDiskAccess {
    /// Files only readable with Full Disk Access. The first one that exists
    /// decides the answer.
    static func probeFiles(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
            home.appendingPathComponent("Library/Safari/CloudTabs.db"),
            home.appendingPathComponent("Library/Safari/Bookmarks.plist"),
        ]
    }

    /// Whether this process can read protected files. Attempting the read also
    /// makes macOS list the app in System Settings › Privacy & Security ›
    /// Full Disk Access, so the user can find the switch.
    static func isGranted() -> Bool {
        for file in probeFiles() where FileManager.default.fileExists(atPath: file.path) {
            let descriptor = open(file.path, O_RDONLY)
            guard descriptor >= 0 else { return false }
            close(descriptor)
            return true
        }
        // Nothing to probe; Mail's folder is protected the same way.
        let mail = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mail")
        return (try? FileManager.default.contentsOfDirectory(atPath: mail.path)) != nil
    }

    /// macOS applies a new grant only to processes started afterwards. A child
    /// process sees it immediately, which tells the app it should relaunch.
    static func isGrantedForNewProcesses() async -> Bool {
        guard let file = probeFiles().first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return isGranted()
        }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/head")
            process.arguments = ["-c", "1", file.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    @MainActor
    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Starts a new copy of the app and quits this one, so a fresh grant
    /// applies.
    @MainActor
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
