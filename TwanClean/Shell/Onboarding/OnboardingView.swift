import SwiftUI

/// The first run: what Twan Clean promises, Full Disk Access, notifications.
struct OnboardingView: View {
    let onFinish: () -> Void
    @StateObject private var permissions = PermissionCoordinator()
    @State private var page = 0
    @State private var notificationsRequested = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: welcome
                case 1: PermissionStepView(permissions: permissions)
                default: notifications
                }
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)

            Divider()
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if page > 0 {
                    Button("Back") { page -= 1 }
                }
                if page < 2 {
                    Button(page == 1 && permissions.state != .granted ? "Later" : "Continue") { page += 1 }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Start Using Twan Clean", action: onFinish)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Welcome to Twan Clean")
                .font(.largeTitle.bold())
            promise("hand.raised", "Nothing is removed without you",
                    "Every scan only lists what it found. You choose what goes.")
            promise("trash", "Your files go to the Trash",
                    "Apps, documents and leftovers can be restored. Only caches and logs that apps rebuild are deleted outright.")
            promise("lock.shield", "Your data stays on this Mac",
                    "No account, no tracking, nothing sent anywhere.")
        }
    }

    private var notifications: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "bell.badge")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Hear about scheduled scans")
                .font(.largeTitle.bold())
            Text("If you turn on scheduled cleaning in Settings, Twan Clean can tell you what it found or freed. This is optional.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(notificationsRequested ? "Notifications Requested" : "Allow Notifications") {
                notificationsRequested = true
                Task { _ = await NotificationService.requestAuthorization() }
            }
            .disabled(notificationsRequested)
        }
    }

    private func promise(_ icon: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Explains Full Disk Access and follows the switch in System Settings.
struct PermissionStepView: View {
    @ObservedObject var permissions: PermissionCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Give Twan Clean Full Disk Access")
                .font(.largeTitle.bold())
            Text("macOS protects folders such as Mail, Desktop, Documents and other apps' data. Without this access, Twan Clean skips them and shows them as locked, so it never interrupts you with permission prompts.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch permissions.state {
            case .granted:
                Label("Full Disk Access is on.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            case .needsRelaunch:
                Label("Access is on. Restart Twan Clean to use it.", systemImage: "arrow.clockwise.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.headline)
                Button("Restart Twan Clean") { AppRelaunch.relaunch() }
            case .notGranted:
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Open Privacy & Security › Full Disk Access.")
                    Text("2. Turn on Twan Clean. If it is not listed, add it with the + button from the Applications folder.")
                }
                .font(.callout)
                Button("Open System Settings") {
                    FullDiskAccess.openSystemSettings()
                    permissions.startPolling()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onDisappear { permissions.stopPolling() }
    }
}
