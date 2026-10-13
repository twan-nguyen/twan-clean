import AppKit

/// Opens the Settings window from places outside any scene, such as the menu
/// bar popover. On macOS 14 and later the window can only be opened through
/// the `openSettings` action, which exists inside a scene, so the main window
/// hands it over here when it appears. On macOS 13 the responder action works.
@MainActor
enum SettingsOpener {
    static var open: () -> Void = {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
