import SwiftUI

struct TwanCleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindow()
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1000, height: 680)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
        }
    }
}
