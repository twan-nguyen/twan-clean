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
    @AppStorage(AppearanceMode.storageKey) private var appearance: AppearanceMode = .system
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var language = AppLanguage.current
    @State private var languageChanged = false
    @StateObject private var permissions = PermissionCoordinator()

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: appearance) { $0.apply() }
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: language) { newValue in
                    newValue.apply()
                    languageChanged = true
                }
                if languageChanged {
                    HStack {
                        Text("Applies after a restart.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart Now") { AppRelaunch.relaunch() }
                    }
                }
            }
            Section {
                switch permissions.state {
                case .granted:
                    Label("Full Disk Access is on", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .needsRelaunch:
                    HStack {
                        Label("Full Disk Access is on after a restart", systemImage: "arrow.clockwise.circle")
                        Spacer()
                        Button("Restart Now") { AppRelaunch.relaunch() }
                    }
                case .notGranted:
                    HStack {
                        Label("Full Disk Access is off", systemImage: "lock.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open System Settings") {
                            FullDiskAccess.openSystemSettings()
                            permissions.startPolling()
                        }
                    }
                }
            }
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
        .task { await permissions.refresh() }
        .onDisappear { permissions.stopPolling() }
    }
}
