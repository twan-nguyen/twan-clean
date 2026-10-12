import SwiftUI

/// One category: scan it alone, review its items and clean the selection.
struct CategoryDetailView: View {
    let category: CleanupCategoryID
    @EnvironmentObject private var model: SmartScanViewModel
    @State private var confirming = false

    private var result: CategoryResult? { model.results[category] }
    private var showsFooter: Bool { !isScanningThis && !(result?.items.isEmpty ?? true) }
    private var isScanningThis: Bool { model.isScanning && model.scanningCategories.contains(category) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                header
                content
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, showsFooter ? 12 : 20)
            if showsFooter {
                footer
            }
        }
        .navigationTitle(Text(category.title))
        .sheet(isPresented: $confirming) {
            CleanConfirmView(items: model.selectedItems(in: [category])) {
                Task { await model.clean([category]) }
            }
        }
        .alert(Text(model.notice ?? ""), isPresented: Binding(get: { model.notice != nil },
                                                             set: { if !$0 { model.notice = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .sheet(item: $model.outcome) { outcome in
            CleanupOutcomeView(outcome: outcome) {
                Task { await model.retryWithAdministrator(outcome) }
            }
        }
    }

    private var header: some View {
        CardSurface(padding: 18, raised: true) {
            HStack(alignment: .center, spacing: 16) {
                IconTile(systemName: category.systemImage, tint: category.tint, size: 52, corner: 14, glow: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.title).font(.system(size: 20, weight: .bold))
                    HStack(spacing: 6) {
                        Text(category.summary)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                        if let note = category.note {
                            InfoButton(resource: note)
                        }
                    }
                }
                Spacer()
                if let result {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(result.totalBytes.formattedBytes)
                            .font(.system(size: 22, weight: .semibold))
                            .monospacedDigit()
                        Text("\(result.items.count) items")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Button {
                    model.scan([category])
                } label: {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PillButtonStyle())
                .disabled(model.isScanning || model.phase == .cleaning)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isScanningThis {
            ScanProgressView(finished: model.finishedCount, total: model.scanningCategories.count,
                             reporter: model.progress) { model.cancelScan() }
            Spacer()
        } else if let result {
            notices(for: result)
            if result.items.isEmpty {
                EmptyStateCard(systemImage: "checkmark.seal.fill", title: "Nothing to clean here")
            } else {
                itemList(result.items)
            }
        } else {
            EmptyStateCard(systemImage: category.systemImage, tint: category.tint, title: "Not scanned yet")
                .overlay(alignment: .bottom) {
                    Button("Scan \(String(localized: category.title))") { model.scan([category]) }
                        .buttonStyle(GlowButtonStyle())
                        .disabled(model.isScanning)
                        .padding(.bottom, 60)
                }
        }
    }

    @ViewBuilder
    private func notices(for result: CategoryResult) -> some View {
        if !result.unreadableLocations.isEmpty {
            FullDiskAccessBanner(unreadableCount: result.unreadableLocations.count)
        }
        if let reclaimable = result.dockerReclaimableBytes, reclaimable > 0 {
            HStack(spacing: 6) {
                Label("Docker can free \(reclaimable.formattedBytes) more", systemImage: "shippingbox")
                InfoButton("Unused images, containers and build cache. Free them with “docker system prune” in Terminal, so Docker stays consistent.")
            }
                .font(.callout)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tint.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func itemList(_ items: [CleanableItem]) -> some View {
        List(items) { item in
            CleanableItemRow(item: item, isSelected: Binding(
                get: { model.isSelected(item) },
                set: { model.setSelected(item, $0) }))
        }
        .listStyle(.inset)
        .cardList()
    }

    private var footer: some View {
        SelectionFooter(selectedBytes: model.selectedBytes(in: [category]), isBusy: model.phase == .cleaning) {
            Button("Select All") { model.setAllSelected(in: category, true) }
                .buttonStyle(PillButtonStyle())
            Button("Select None") { model.setAllSelected(in: category, false) }
                .buttonStyle(PillButtonStyle())
        } action: {
            Button {
                confirming = true
            } label: {
                Label("Clean…", systemImage: "sparkles")
            }
            .buttonStyle(GlowButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(model.selectedItems(in: [category]).isEmpty || model.phase != .ready)
        }
    }
}
