import SwiftUI

struct OrphansView: View {
    @EnvironmentObject private var model: OrphansViewModel
    @State private var confirming = false
    @State private var showingIgnored = false

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                start
            case .scanning:
                ScrollView {
                    WorkingCard(tint: Tint.pink, systemImage: "questionmark.folder.fill",
                                title: "Comparing Library folders with your installed apps…") {
                        EmptyView()
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 920)
                    .frame(maxWidth: .infinity)
                }
            case .ready, .removing:
                if model.items.isEmpty {
                    EmptyStateCard(systemImage: "checkmark.seal.fill", title: "No orphaned files found")
                        .overlay(alignment: .topTrailing) { toolbarButtons.padding(16) }
                } else {
                    results
                }
            }
        }
        .navigationTitle("Orphaned Files")
        .confirmationDialog(Text("Move \(model.selectedItems.count) items to the Trash?"), isPresented: $confirming) {
            Button("Move to Trash (\(model.selectedBytes.formattedBytes))", role: .destructive) {
                Task { await model.trashSelection() }
            }
        } message: {
            Text("You can restore them from the Trash. The space is freed when you empty it.")
        }
        .sheet(item: $model.outcome) { outcome in
            CleanupOutcomeView(outcome: outcome) {
                Task { await model.retryWithAdministrator(outcome) }
            }
        }
        .sheet(isPresented: $showingIgnored) {
            IgnoredOrphansView(model: model)
        }
    }

    private var start: some View {
        ScrollView {
            ToolIntroCard(systemImage: "questionmark.folder.fill", tint: Tint.pink,
                          title: "Find files left by deleted apps",
                          message: "Twan Clean compares caches, logs and saved states with the apps installed now. Nothing is selected for you, and removed files go to the Trash.") {
                Button { model.scan() } label: { Label("Scan", systemImage: "magnifyingglass") }
                    .buttonStyle(GlowButtonStyle(tint: Tint.pink, gradient: TintGradient.of(Tint.pink)))
                    .keyboardShortcut(.defaultAction)
                if !model.ignored.isEmpty {
                    Button { showingIgnored = true } label: {
                        Label("Ignored (\(model.ignored.count))", systemImage: "eye.slash")
                    }
                    .buttonStyle(PillButtonStyle())
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var toolbarButtons: some View {
        HStack(spacing: 8) {
            Button {
                showingIgnored = true
            } label: {
                Label("Ignored (\(model.ignored.count))", systemImage: "eye.slash")
            }
            .buttonStyle(PillButtonStyle())
            .disabled(model.ignored.isEmpty)
            Button {
                model.scan()
            } label: {
                Label("Scan Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PillButtonStyle())
            .disabled(model.phase == .scanning || model.phase == .removing)
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardSurface(padding: 18, raised: true) {
                HStack(spacing: 14) {
                    IconTile(systemName: "questionmark.folder.fill", tint: Tint.pink, size: 44, corner: 12, glow: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.items.reduce(0) { $0 + $1.bytes }.formattedBytes)
                            .font(.system(size: 24, weight: .semibold))
                            .monospacedDigit()
                        Text("\(model.items.count) items from apps that are no longer installed")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    toolbarButtons
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            List {
                ForEach(model.groups, id: \.location) { group in
                    Section {
                        ForEach(group.items) { item in
                            row(item)
                        }
                    } header: {
                        HStack(spacing: 8) {
                            IconTile(systemName: "folder.fill", tint: Tint.pink, size: 20, corner: 5)
                            Text(verbatim: (group.location.path as NSString).abbreviatingWithTildeInPath)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(group.items.reduce(0) { $0 + $1.bytes }.formattedBytes)
                                .font(.system(size: 11.5, weight: .semibold))
                                .monospacedDigit()
                        }
                    }
                }
            }
            .listStyle(.inset)
            .cardList()
            .padding(.horizontal, 20)

            SelectionFooter(selectedBytes: model.selectedBytes, isBusy: model.phase == .removing) {
                Button {
                    confirming = true
                } label: {
                    Label("Move to Trash…", systemImage: "trash")
                }
                .buttonStyle(GlowButtonStyle.destructive)
                .disabled(model.selectedItems.isEmpty || model.phase != .ready)
            }
        }
    }

    private func row(_ item: OrphanItem) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(get: { model.selection.contains(item.id) },
                                 set: { model.setSelected(item, $0) })) {
                EmptyView()
            }
            .toggleStyle(.tintedCheckbox(Tint.pink))
            .accessibilityLabel(Text(item.name))
            IconTile(systemName: item.isDirectory ? "folder.fill" : "doc.fill", tint: Tint.pink, size: 22, corner: 6)
            Text(item.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            if item.requiresAdministrator {
                StatusChip(label: String(localized: "Needs password"), tint: Tint.orange)
            }
            Spacer()
            if let date = item.lastModified {
                Text(date, format: .dateTime.year().month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(item.bytes.formattedBytes)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.vertical, 1)
        .contextMenu {
            Button("Always Ignore") { model.ignore(item) }
            Button("Show in Finder") { Finder.reveal([item.url]) }
        }
    }
}

private struct IgnoredOrphansView: View {
    @ObservedObject var model: OrphansViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ignored Items")
                .font(.title2.bold())
            List {
                ForEach(model.ignored.sorted(), id: \.self) { path in
                    HStack {
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Stop Ignoring") { model.stopIgnoring(path) }
                    }
                }
            }
            .frame(minHeight: 200)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
