import SwiftUI

struct TwanCleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindow()
                .frame(minWidth: MainWindow.minimumSize.width, minHeight: MainWindow.minimumSize.height)
                .environmentObject(model)
                .environmentObject(model.smartScan)
                .environmentObject(model.spaceLens)
                .environmentObject(model.uninstaller)
                .environmentObject(model.orphans)
                .modifier(MainWindowRegistration(model: model, appDelegate: appDelegate))
        }
        .defaultSize(MainWindow.recommendedSize)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
        }

    }
}

/// Hands the app model to the delegate and remembers how to reopen the main
/// window, which the menu bar needs after the window was closed.
private struct MainWindowRegistration: ViewModifier {
    let model: AppModel
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            model.openMainWindow = { openWindow(id: "main") }
            appDelegate.model = model
        }
    }
}
