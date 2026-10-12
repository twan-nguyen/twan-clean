import SwiftUI

struct TwanCleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindow()
                .frame(minWidth: 900, minHeight: 600)
                .environmentObject(model)
                .environmentObject(model.smartScan)
                .environmentObject(model.spaceLens)
        }
        .defaultSize(width: 1000, height: 680)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
        }
    }
}
