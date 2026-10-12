import SwiftUI

enum MenuBarSettings {
    static let showKey = "menuBar.show"

    static var isShown: Bool {
        UserDefaults.standard.object(forKey: showKey) as? Bool ?? true
    }
}

/// The window behind the menu bar icon: disk space, the scheduled run and
/// shortcuts into the app.
struct MenuBarPanel: View {
    @ObservedObject var appModel: AppModel
    /// Closes the popover before acting.
    let dismiss: () -> Void
    @State private var disk = DiskSpace.current()
    @State private var schedule = ScheduleStore().loadSettings()
    @State private var summary = ScheduleStore().loadSummary()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Twan Clean")
                .font(.headline)
            if let disk {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(disk.usedBytes), total: Double(max(disk.totalBytes, 1)))
                    Text("\(disk.availableBytes.formattedBytes) available of \(disk.totalBytes.formattedBytes)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            if let summary {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last scheduled scan")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(summary.date, format: .relative(presentation: .named)): found \(summary.foundBytes.formattedBytes)")
                    if summary.cleanedBytes > 0 {
                        Text("Cleaned \(summary.cleanedBytes.formattedBytes)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if schedule.isEnabled {
                Text("Next: \(schedule.nextRun(now: Date()), format: .dateTime.weekday().hour().minute())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button {
                dismiss()
                appModel.showMainWindow(.smartScan)
                appModel.smartScan.scan()
            } label: {
                Label("Smart Scan", systemImage: "sparkles")
            }
            Button {
                dismiss()
                appModel.showMainWindow()
            } label: {
                Label("Open Twan Clean", systemImage: "macwindow")
            }
            Button {
                dismiss()
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            Divider()
            Button("Quit Twan Clean") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .padding(14)
        .frame(width: 280)
        .onAppear {
            disk = DiskSpace.current()
            schedule = ScheduleStore().loadSettings()
            summary = ScheduleStore().loadSummary()
        }
    }
}
