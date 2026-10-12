import Charts
import SwiftUI

/// The Smart Scan home: scan every category at once and clean the selection.
struct SmartScanView: View {
    /// Opens a category's page, remembering Smart Scan as the way back.
    let open: (SidebarItem) -> Void
    @EnvironmentObject private var model: SmartScanViewModel
    @State private var disk = DiskSpace.current()
    @State private var confirming = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch model.phase {
                case .idle:
                    start
                case .scanning:
                    ScanProgressView(finished: model.finishedCount, total: model.scanningCategories.count,
                                     reporter: model.progress) { model.cancelScan() }
                case .ready, .cleaning:
                    results
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: model.phase)
        }
        .navigationTitle("Smart Scan")
        .sheet(isPresented: $confirming) {
            CleanConfirmView(items: model.selectedItems()) {
                Task { await model.clean() }
            }
        }
        .alert(Text(model.notice ?? ""), isPresented: Binding(get: { model.notice != nil },
                                                             set: { if !$0 { model.notice = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .sheet(item: $model.outcome, onDismiss: { disk = DiskSpace.current() }) { outcome in
            CleanupOutcomeView(outcome: outcome) {
                Task { await model.retryWithAdministrator(outcome) }
            }
        }
        .onAppear { disk = DiskSpace.current() }
    }

    // MARK: - Start

    @ViewBuilder
    private var start: some View {
        if let disk {
            DiskSummaryCard(disk: disk) { model.scan() }
        } else {
            ToolIntroCard(systemImage: "sparkles", tint: Tint.teal,
                          title: "Find junk in \(CleanupCategoryID.allCases.count) places at once",
                          message: "Nothing is removed until you review the results and choose what to clean.") {
                Button { model.scan() } label: { Label("Smart Scan", systemImage: "sparkles") }
                    .buttonStyle(GlowButtonStyle())
            }
        }
        SectionHeader("What Smart Scan checks")
        Text("Nothing is removed until you review the results and choose what to clean.")
            .font(.callout)
            .foregroundStyle(.secondary)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
            ForEach(CleanupCategoryID.allCases) { category in
                Button {
                    open(.category(category))
                } label: {
                    CardSurface(padding: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            IconTile(systemName: category.systemImage, tint: category.tint, size: 32, corner: 8)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(category.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(category.summary)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        resultHero
        if model.totalFoundBytes > 0 {
            SectionHeader("By category")
            CardSurface(padding: 18) {
                CategoryBarChart(results: sortedResults.filter { $0.totalBytes > 0 }) { open(.category($0)) }
            }
            CardSurface(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(sortedResults, id: \.category) { result in
                        CategoryToggleRow(result: result) { open(.category(result.category)) }
                        if result.category != sortedResults.last?.category {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var resultHero: some View {
        let unreadable = model.results.values.reduce(0) { $0 + $1.unreadableLocations.count }
        return CardSurface(padding: 24, raised: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if model.totalFoundBytes > 0 {
                        Text(model.totalFoundBytes.formattedBytes)
                            .font(.system(size: 40, weight: .semibold))
                            .monospacedDigit()
                        Text("found")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    } else {
                        Label {
                            Text("Your Mac is clean")
                        } icon: {
                            Image(systemName: "checkmark.seal.fill")
                        }
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Tint.green)
                    }
                    Spacer()
                    Button {
                        model.scan()
                    } label: {
                        Label("Scan Again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(PillButtonStyle())
                    .disabled(model.phase != .ready)
                }
                if let date = model.lastScanDate {
                    Text("Scanned \(date, format: .relative(presentation: .named))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if model.totalFoundBytes > 0 {
                    HStack(spacing: 12) {
                        if model.phase == .cleaning {
                            ProgressView().controlSize(.small)
                            Text("Cleaning…").foregroundStyle(.secondary)
                        } else {
                            Button {
                                confirming = true
                            } label: {
                                Label("Clean \(model.selectedBytes().formattedBytes)", systemImage: "sparkles")
                            }
                            .buttonStyle(GlowButtonStyle())
                            .disabled(model.selectedItems().isEmpty)
                            Text("\(model.selectedItems().count) items selected")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                if unreadable > 0 {
                    FullDiskAccessBanner(unreadableCount: unreadable)
                }
            }
        }
    }

    private var sortedResults: [CategoryResult] {
        model.results.values.sorted { $0.totalBytes > $1.totalBytes }
    }
}

/// Horizontal bars, one per category, in the category's colour.
private struct CategoryBarChart: View {
    let results: [CategoryResult]
    let onSelect: (CleanupCategoryID) -> Void

    private struct Bar: Identifiable {
        let category: CleanupCategoryID
        let bytes: Int64
        var id: CleanupCategoryID { category }
        var name: String { String(localized: category.title) }
    }

    private var bars: [Bar] {
        results.prefix(8).map { Bar(category: $0.category, bytes: $0.totalBytes) }
    }

    var body: some View {
        // Headroom so the size label on the longest bar is not clipped.
        let upper = max(1, Double(bars.map(\.bytes).max() ?? 0) * 1.3)
        Chart(bars) { bar in
            BarMark(x: .value("Size", Double(bar.bytes)), y: .value("Category", bar.name))
                .foregroundStyle(bar.category.tint.gradient)
                .cornerRadius(5)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(bar.bytes.formattedBytes)
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
        }
        .chartXScale(domain: 0...upper)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(preset: .aligned, position: .leading) { _ in AxisValueLabel() }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let origin = geo[proxy.plotAreaFrame].origin
                        if let name: String = proxy.value(atY: location.y - origin.y),
                           let bar = bars.first(where: { $0.name == name }) {
                            onSelect(bar.category)
                        }
                    }
            }
        }
        .frame(height: max(110, CGFloat(bars.count) * 32))
    }
}

/// A category in the results: tick it to select all its items, click the
/// rest of the row to review them.
private struct CategoryToggleRow: View {
    let result: CategoryResult
    let onOpen: () -> Void
    @EnvironmentObject private var model: SmartScanViewModel
    @State private var hovering = false

    private var selectedCount: Int { result.items.filter { model.isSelected($0) }.count }

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(get: { !result.items.isEmpty && selectedCount == result.items.count },
                                 set: { model.setAllSelected(in: result.category, $0) })) {
                EmptyView()
            }
            .toggleStyle(.tintedCheckbox(result.category.tint))
            .disabled(result.items.isEmpty || model.phase != .ready)
            .help(Text("Select all in this category"))

            Button(action: onOpen) {
                HStack(spacing: 12) {
                    IconTile(systemName: result.category.systemImage, tint: result.category.tint, size: 30, corner: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(result.category.title)
                                .font(.system(size: 13.5, weight: .semibold))
                            if !result.unreadableLocations.isEmpty {
                                StatusChip(label: String(localized: "Locked"), systemImage: "lock.fill", tint: Tint.orange)
                            }
                            if !result.items.isEmpty, !result.items.contains(where: \.selectedByDefault) {
                                StatusChip(label: String(localized: "Review first"), tint: Tint.yellow)
                            }
                        }
                        Text("\(result.items.count) items · \(selectedCount) selected")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer()
                    Text(result.totalBytes.formattedBytes)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .opacity(hovering ? 1 : 0.5)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(hovering ? 0.04 : 0))
            .padding(.horizontal, 6))
        .onHover { hovering = $0 }
    }
}
