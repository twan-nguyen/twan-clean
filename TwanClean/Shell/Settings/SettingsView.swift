import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ScanSettingsTab()
                .tabItem { Label("Scanning", systemImage: "magnifyingglass") }
            ScheduleSettingsTab()
                .tabItem { Label("Schedule", systemImage: "calendar.badge.clock") }
        }
        .frame(width: 540, height: 520)
    }
}

private struct GeneralSettingsTab: View {
    @AppStorage(MenuBarSettings.showKey) private var showInMenuBar = true
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Toggle("Open at login", isOn: Binding(get: { openAtLogin }, set: { enabled in
                do {
                    try LoginItem.setEnabled(enabled)
                    loginError = nil
                } catch {
                    loginError = error.localizedDescription
                }
                openAtLogin = LoginItem.isEnabled
            }))
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }
            Toggle("Show in menu bar", isOn: $showInMenuBar)
            LabeledContent("Version", value: version)
        }
        .formStyle(.grouped)
    }
}
