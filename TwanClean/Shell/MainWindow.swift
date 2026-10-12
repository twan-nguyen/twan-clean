import SwiftUI

struct MainWindow: View {
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
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            detail(for: selection ?? .smartScan)
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
        FeaturePlaceholderView(item: item)
    }
}

/// Stands in for a feature screen until that feature is implemented.
private struct FeaturePlaceholderView: View {
    let item: SidebarItem

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(item.title)
                .font(.title2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(Text(item.title))
    }
}
