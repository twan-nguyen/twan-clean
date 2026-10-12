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
            .padding(32)
            .frame(maxWidth: 600)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 14, y: 4)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<3) { index in
                        Capsule()
                            .fill(index == page ? Tint.teal : Color.secondary.opacity(0.3))
                            .frame(width: index == page ? 18 : 7, height: 7)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: page)
                Spacer()
                if page > 0 {
                    Button("Back") { page -= 1 }
                        .buttonStyle(PillButtonStyle())
                }
                if page < 2 {
                    Button(page == 1 && permissions.state != .granted ? "Later" : "Continue") { page += 1 }
                        .buttonStyle(GlowButtonStyle())
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Start Using Twan Clean", action: onFinish)
                        .buttonStyle(GlowButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)
        }
        .background(AmbientBackground())
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            Text("Welcome to Twan Clean")
                .font(.system(size: 28, weight: .bold))
            promise("hand.raised.fill", Tint.teal, "Nothing is removed without you",
                    "Every scan only lists what it found. You choose what goes.")
            promise("trash.fill", Tint.blue, "Your files go to the Trash",
                    "Apps, documents and leftovers can be restored. Only caches and logs that apps rebuild are deleted outright.")
            promise("lock.shield.fill", Tint.purple, "Your data stays on this Mac",
                    "No account, no tracking, nothing sent anywhere.")
        }
    }

    private var notifications: some View {
        VStack(alignment: .leading, spacing: 18) {
            IconTile(systemName: "bell.badge.fill", tint: Tint.orange, size: 64, corner: 16, glow: true)
            Text("Hear about scheduled scans")
                .font(.system(size: 28, weight: .bold))
            Text("If you turn on scheduled cleaning in Settings, Twan Clean can tell you what it found or freed. This is optional.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(notificationsRequested ? "Notifications Requested" : "Allow Notifications") {
                notificationsRequested = true
                Task { _ = await NotificationService.requestAuthorization() }
            }
            .buttonStyle(PillButtonStyle())
            .disabled(notificationsRequested)
        }
    }

    private func promise(_ icon: String, _ tint: Color, _ title: LocalizedStringKey,
                         _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(systemName: icon, tint: tint, size: 34, corner: 9)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
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
            IconTile(systemName: "lock.shield.fill", tint: Tint.teal, size: 64, corner: 16, glow: true)
            Text("Give Twan Clean Full Disk Access")
                .font(.system(size: 28, weight: .bold))
            Text("macOS protects folders such as Mail, Desktop, Documents and other apps' data. Without this access, Twan Clean skips them and shows them as locked, so it never interrupts you with permission prompts.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch permissions.state {
            case .granted:
                Label("Full Disk Access is on.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Tint.green)
                    .font(.headline)
            case .needsRelaunch:
                Label("Access is on. Restart Twan Clean to use it.", systemImage: "arrow.clockwise.circle.fill")
                    .foregroundStyle(Tint.orange)
                    .font(.headline)
                Button("Restart Twan Clean") { AppRelaunch.relaunch() }
                    .buttonStyle(PillButtonStyle())
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
                .buttonStyle(PillButtonStyle())
            }
        }
        .onDisappear { permissions.stopPolling() }
    }
}
