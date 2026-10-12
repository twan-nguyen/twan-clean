import SwiftUI

struct MainWindow: View {
    @AppStorage("onboarding.completed") private var onboardingCompleted = false
    @AppStorage(AppearanceMode.storageKey) private var appearance: AppearanceMode = .system

    var body: some View {
        Group {
            if onboardingCompleted {
                MainSplitView(appearance: $appearance)
            } else {
                OnboardingView { onboardingCompleted = true }
            }
        }
        .onAppear { appearance.apply() }
        .onChange(of: appearance) { $0.apply() }
    }
}

private struct MainSplitView: View {
    @Binding var appearance: AppearanceMode
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var smartScan: SmartScanViewModel
    @EnvironmentObject private var spaceLens: SpaceLensViewModel
    @EnvironmentObject private var uninstaller: UninstallerViewModel
    @EnvironmentObject private var orphans: OrphansViewModel
    @StateObject private var permissions = PermissionCoordinator()
    @State private var selection: SidebarItem? = .smartScan
    /// Set while the user is on a page reached from Smart Scan's results:
    /// where they went and where the Back button returns.
    @State private var backTarget: SidebarItem?
    @State private var backReturn: SidebarItem?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    Section("Overview") {
                        row(.smartScan, badge: smartScan.totalFoundBytes > 0 ? smartScan.totalFoundBytes.formattedBytes : nil)
                        row(.spaceLens, badge: spaceLens.root.map { $0.bytes.formattedBytes })
                    }
                    Section("Applications") {
                        row(.uninstaller, badge: uninstaller.apps.isEmpty ? nil : "\(uninstaller.apps.count)")
                        row(.orphans, badge: orphans.items.isEmpty ? nil : "\(orphans.items.count)")
                    }
                    Section("Cleanup") {
                        ForEach(CleanupCategoryID.allCases) { category in
                            row(.category(category), badge: categoryBadge(category))
                        }
                    }
                }
                .listStyle(.sidebar)
                Divider()
                PermissionFooter(permissions: permissions)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 236)
        } detail: {
            detail(for: selection ?? .smartScan)
                .id(selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AmbientBackground())
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                AppearancePill(selection: $appearance)
            }
            ToolbarItem(placement: .navigation) {
                if let backReturn, selection == backTarget {
                    Button {
                        selection = backReturn
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .labelStyle(.titleAndIcon)
                    }
                    .help(Text("Back to \(String(localized: backReturn.title))"))
                }
            }
        }
        .onChange(of: selection) { newValue in
            // Going anywhere else, from the sidebar or with Back itself,
            // ends the detour.
            if newValue != backTarget {
                backTarget = nil
                backReturn = nil
            }
        }
        .onReceive(appModel.$route.compactMap { $0 }) { route in
            selection = route
            appModel.route = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await permissions.refresh() }
        }
        .task { await permissions.refresh() }
        .onDisappear { permissions.stopPolling() }
    }

    private func row(_ item: SidebarItem, badge: String?) -> some View {
        SidebarRow(item: item, badge: badge, isSelected: selection == item)
            .tag(item)
    }

    private func categoryBadge(_ category: CleanupCategoryID) -> String? {
        guard let bytes = smartScan.results[category]?.totalBytes, bytes > 0 else { return nil }
        return bytes.formattedBytes
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .smartScan:
            SmartScanView { target in
                backReturn = .smartScan
                backTarget = target
                selection = target
            }
        case .category(let category):
            CategoryDetailView(category: category)
        case .spaceLens:
            SpaceLensView()
        case .uninstaller:
            UninstallerView()
        case .orphans:
            OrphansView()
        }
    }
}

private struct SidebarRow: View {
    let item: SidebarItem
    let badge: String?
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 9) {
            IconTile(systemName: item.systemImage, tint: item.tint, size: 22, corner: 6, glow: isSelected)
            Text(item.title)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                // A solid colour: the sidebar's vibrant default can turn the
                // label invisible with some accent and transparency settings.
                .foregroundStyle(labelColor)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let badge {
                Text(badge)
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? labelColor : .secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }

    private var labelColor: Color {
        colorScheme == .dark ? .white.opacity(0.92) : .black.opacity(0.85)
    }
}

/// Whether Twan Clean can read everything, with the fix one click away.
private struct PermissionFooter: View {
    @ObservedObject var permissions: PermissionCoordinator

    var body: some View {
        HStack(spacing: 10) {
            PulsingDot(tint: tint, isPulsing: permissions.state != .granted)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            switch permissions.state {
            case .granted:
                EmptyView()
            case .notGranted:
                Button("Fix") {
                    FullDiskAccess.openSystemSettings()
                    permissions.startPolling()
                }
                .controlSize(.small)
            case .needsRelaunch:
                Button("Relaunch") { AppRelaunch.relaunch() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private var tint: Color { permissions.state == .granted ? Tint.green : Tint.orange }

    private var title: LocalizedStringKey {
        switch permissions.state {
        case .granted: "Ready to clean"
        case .notGranted: "Limited access"
        case .needsRelaunch: "Relaunch to finish"
        }
    }

    private var subtitle: LocalizedStringKey {
        switch permissions.state {
        case .granted: "Full Disk Access granted"
        case .notGranted: "Protected folders are skipped"
        case .needsRelaunch: "Full Disk Access applies after a relaunch"
        }
    }
}
