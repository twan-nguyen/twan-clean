import SwiftUI

struct MainWindow: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selection: SidebarItem? = .smartScan

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Overview") {
                    row(.smartScan)
                    row(.spaceLens)
                }
                Section("Applications") {
                    row(.uninstaller)
                    row(.orphans)
                }
                Section("Cleanup") {
                    ForEach(CleanupCategoryID.allCases) { category in
                        row(.category(category))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            detail(for: selection ?? .smartScan)
        }
        .onReceive(appModel.$route.compactMap { $0 }) { route in
            selection = route
            appModel.route = nil
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        Label {
            Text(item.title)
        } icon: {
            Image(systemName: item.systemImage)
        }
        .tag(item)
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .smartScan:
            SmartScanView(selection: $selection)
        case .category(let category):
            CategoryDetailView(category: category)
                .id(category)
        case .spaceLens:
            SpaceLensView()
        case .uninstaller:
            UninstallerView()
        case .orphans:
            OrphansView()
        }
    }
}
