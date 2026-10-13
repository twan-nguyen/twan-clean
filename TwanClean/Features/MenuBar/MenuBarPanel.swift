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
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 28, height: 28)
                Text("Twan Clean")
                    .font(.system(size: 14, weight: .bold))
            }
            if let disk {
                VStack(alignment: .leading, spacing: 6) {
                    let used = Double(disk.usedBytes) / Double(max(disk.totalBytes, 1))
                    GradientProgressBar(progress: used, tint: used >= 0.85 ? Tint.orange : Tint.teal)
                    Text("\(disk.availableBytes.formattedBytes) available of \(disk.totalBytes.formattedBytes)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
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
                nextRunLabel
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
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlowButtonStyle())
            Button {
                dismiss()
                appModel.showMainWindow()
            } label: {
                Label("Open Twan Clean", systemImage: "macwindow")
            }
            Button {
                dismiss()
                NSApp.activate(ignoringOtherApps: true)
                SettingsOpener.open()
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

    /// A day, not just a weekday: a monthly run is weeks away. A run that is
    /// already due starts at the next hourly check, never at a time in the past.
    @ViewBuilder
    private var nextRunLabel: some View {
        if let next = schedule.upcomingRun(now: Date()) {
            Text("Next: \(next, format: .dateTime.weekday().day().month().hour().minute())")
        } else {
            Text("Next: within the hour")
        }
    }
}
