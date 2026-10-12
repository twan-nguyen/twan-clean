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
                ProgressView("Comparing Library folders with your installed apps…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready, .removing:
                if model.items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 40))
                            .foregroundStyle(.green)
                        Text("No orphaned files found")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    results
                }
            }
        }
        .navigationTitle("Orphaned Files")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showingIgnored = true
                } label: {
                    Label("Ignored (\(model.ignored.count))", systemImage: "eye.slash")
                }
                .disabled(model.ignored.isEmpty)
                Button {
                    model.scan()
                } label: {
                    Label("Scan Again", systemImage: "arrow.clockwise")
                }
                .disabled(model.phase == .scanning || model.phase == .removing)
            }
        }
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
        VStack(spacing: 14) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("Find files left by deleted apps")
                .font(.title2.bold())
            Text("Twan Clean compares caches, logs and saved states with the apps installed now. Nothing is selected for you, and removed files go to the Trash.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Button("Scan") { model.scan() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var results: some View {
        VStack(spacing: 0) {
            List {
                ForEach(model.groups, id: \.location) { group in
                    Section {
                        ForEach(group.items) { item in
                            row(item)
                        }
                    } header: {
                        Text(group.location.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .listStyle(.inset)
            Divider()
            HStack {
                Text("Selected: \(model.selectedBytes.formattedBytes)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                if model.phase == .removing {
                    ProgressView().controlSize(.small)
                }
                Button("Move to Trash…") { confirming = true }
                    .disabled(model.selectedItems.isEmpty || model.phase != .ready)
            }
            .padding(12)
        }
    }

    private func row(_ item: OrphanItem) -> some View {
        HStack(spacing: 8) {
            Toggle(item.name, isOn: Binding(get: { model.selection.contains(item.id) },
                                            set: { model.setSelected(item, $0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            Image(systemName: item.isDirectory ? "folder" : "doc")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
            if item.requiresAdministrator {
                Text("Needs password")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            Spacer()
            if let date = item.lastModified {
                Text(date, format: .dateTime.year().month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(item.bytes.formattedBytes)
                .monospacedDigit()
                .frame(minWidth: 72, alignment: .trailing)
        }
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
