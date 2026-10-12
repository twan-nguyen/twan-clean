import SwiftUI

/// The Smart Scan home: scan every category at once and clean the selection.
struct SmartScanView: View {
    @Binding var selection: SidebarItem?
    @EnvironmentObject private var model: SmartScanViewModel
    @State private var disk = DiskSpace.current()
    @State private var confirming = false

    var body: some View {
        Group {
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
        .navigationTitle("Smart Scan")
        .toolbar {
            ToolbarItem {
                Button {
                    model.scan()
                } label: {
                    Label("Scan Again", systemImage: "arrow.clockwise")
                }
                .disabled(model.phase != .ready)
            }
        }
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
                Task { await model.retryWithAdministrator() }
            }
        }
        .onAppear { disk = DiskSpace.current() }
    }

    private var start: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let disk { DiskSummaryCard(disk: disk) }
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                    Text("Find junk in \(CleanupCategoryID.allCases.count) places at once")
                        .font(.title2.bold())
                    Text("Nothing is removed until you review the results and choose what to clean.")
                        .foregroundStyle(.secondary)
                    Button("Scan") { model.scan() }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .padding(.top, 6)
                }
                .padding(.vertical, 12)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(CleanupCategoryID.allCases) { category in
                        Label {
                            Text(category.title)
                        } icon: {
                            Image(systemName: category.systemImage).foregroundStyle(.tint)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Found \(model.totalFoundBytes.formattedBytes)")
                        .font(.largeTitle.bold())
                        .monospacedDigit()
                    if let date = model.lastScanDate {
                        Text("Scanned \(date, format: .relative(presentation: .named))")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if model.phase == .cleaning {
                    ProgressView().controlSize(.small)
                    Text("Cleaning…")
                } else {
                    Text("Selected: \(model.selectedBytes().formattedBytes)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button("Clean…") { confirming = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(model.selectedItems().isEmpty)
                }
            }
            .padding(20)
            Divider()
            List {
                ForEach(sortedResults, id: \.category) { result in
                    Button {
                        selection = .category(result.category)
                    } label: {
                        categoryRow(result)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.inset)
        }
    }

    private var sortedResults: [CategoryResult] {
        model.results.values.sorted { $0.totalBytes > $1.totalBytes }
    }

    private func categoryRow(_ result: CategoryResult) -> some View {
        let total = max(model.totalFoundBytes, 1)
        return HStack(spacing: 12) {
            Image(systemName: result.category.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(result.category.title).font(.headline)
                    if !result.unreadableLocations.isEmpty {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.orange)
                            .help(Text("Some locations could not be read"))
                    }
                }
                ProgressView(value: Double(result.totalBytes), total: Double(total))
                    .tint(.accentColor)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(result.totalBytes.formattedBytes)
                    .monospacedDigit()
                Text("\(model.selectedBytes(in: [result.category]).formattedBytes) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(minWidth: 110, alignment: .trailing)
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
