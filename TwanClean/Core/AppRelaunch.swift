import AppKit

enum AppRelaunch {
    /// Starts a new copy of the app and quits this one, so a new Full Disk
    /// Access grant or language applies. Stays open if the new copy fails.
    @MainActor
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
