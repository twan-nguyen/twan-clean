import SwiftUI

/// One category: scan it alone, review its items and clean the selection.
struct CategoryDetailView: View {
    let category: CleanupCategoryID
    @EnvironmentObject private var model: SmartScanViewModel
    @State private var confirming = false

    private var result: CategoryResult? { model.results[category] }
    private var isScanningThis: Bool { model.isScanning && model.scanningCategories.contains(category) }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(20)
            Divider()
            content
        }
        .navigationTitle(Text(category.title))
        .toolbar {
            ToolbarItem {
                Button {
                    model.scan([category])
                } label: {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanning || model.phase == .cleaning)
            }
        }
        .sheet(isPresented: $confirming) {
            CleanConfirmView(items: model.selectedItems(in: [category])) {
                Task { await model.clean([category]) }
            }
        }
        .sheet(item: $model.outcome) { outcome in
            CleanupOutcomeView(outcome: outcome) {
                Task { await model.retryWithAdministrator() }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: category.systemImage)
                .font(.system(size: 30))
                .foregroundStyle(.tint)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(category.title).font(.title2.bold())
                Text(category.summary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let result {
                Text(result.totalBytes.formattedBytes)
                    .font(.title2.monospacedDigit())
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isScanningThis {
            ScanProgressView(finished: model.finishedCount, total: model.scanningCategories.count,
                             reporter: model.progress) { model.cancelScan() }
        } else if let result {
            VStack(spacing: 0) {
                notices(for: result)
                if result.items.isEmpty {
                    emptyState
                } else {
                    itemList(result.items)
                    Divider()
                    footer
                }
            }
        } else {
            VStack(spacing: 14) {
                Text("Not scanned yet")
                    .foregroundStyle(.secondary)
                Button("Scan \(String(localized: category.title))") { model.scan([category]) }
                    .controlSize(.large)
                    .disabled(model.isScanning)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func notices(for result: CategoryResult) -> some View {
        VStack(spacing: 8) {
            if !result.unreadableLocations.isEmpty {
                FullDiskAccessBanner(unreadableCount: result.unreadableLocations.count)
            }
            if let reclaimable = result.dockerReclaimableBytes, reclaimable > 0 {
                Label("Docker reports \(reclaimable.formattedBytes) of unused images, containers and build cache. Free it with “docker system prune” so Docker stays consistent.",
                      systemImage: "info.circle")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, result.unreadableLocations.isEmpty && (result.dockerReclaimableBytes ?? 0) == 0 ? 0 : 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("Nothing to clean here")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func itemList(_ items: [CleanableItem]) -> some View {
        List(items) { item in
            CleanableItemRow(item: item, isSelected: Binding(
                get: { model.isSelected(item) },
                set: { model.setSelected(item, $0) }))
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack {
            Button("Select All") { model.setAllSelected(in: category, true) }
            Button("Select None") { model.setAllSelected(in: category, false) }
            Spacer()
            Text("Selected: \(model.selectedBytes(in: [category]).formattedBytes)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button("Clean…") { confirming = true }
                .keyboardShortcut(.defaultAction)
                .disabled(model.selectedItems(in: [category]).isEmpty || model.phase != .ready)
        }
        .padding(12)
    }
}
