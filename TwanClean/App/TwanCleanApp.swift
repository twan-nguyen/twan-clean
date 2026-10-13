import SwiftUI

struct TwanCleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    init() {
        // The saved schedule may say "on" while macOS no longer has the
        // background task, for example after the app was updated.
        SchedulerAgent.reconcileInBackground()
    }

    var body: some Scene {
        // A single window: opening it again brings the existing one forward
        // instead of creating another with its own state.
        Window("Twan Clean", id: "main") {
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
/// window and the Settings window, which the menu bar needs after the window
/// was closed.
private struct MainWindowRegistration: ViewModifier {
    let model: AppModel
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        registeringSettings(content).onAppear {
            model.openMainWindow = { openWindow(id: "main") }
            appDelegate.model = model
        }
    }

    @ViewBuilder
    private func registeringSettings(_ content: Content) -> some View {
        if #available(macOS 14, *) {
            content.modifier(SettingsActionRegistration())
        } else {
            content
        }
    }
}

@available(macOS 14, *)
private struct SettingsActionRegistration: ViewModifier {
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.onAppear { SettingsOpener.open = { openSettings() } }
    }
}
