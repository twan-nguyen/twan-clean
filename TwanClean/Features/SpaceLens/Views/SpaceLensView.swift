import SwiftUI

struct SpaceLensView: View {
    @EnvironmentObject private var model: SpaceLensViewModel
    @State private var confirming = false

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                start
            case .scanning:
                scanning
            case .ready, .removing:
                if let folder = model.current {
                    browser(folder)
                } else {
                    start
                }
            }
        }
        .navigationTitle("Space Lens")
        .toolbar {
            ToolbarItemGroup {
                if model.phase == .ready, (model.path.count) > 1 {
                    Button {
                        model.goUp()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
                Button {
                    chooseFolder()
                } label: {
                    Label("Choose Folder…", systemImage: "folder")
                }
                .disabled(model.phase == .scanning || model.phase == .removing)
                if model.root != nil, model.phase == .ready {
                    Button {
                        model.rescan()
                    } label: {
                        Label("Scan Again", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .confirmationDialog(Text("Move \(model.selection.count) items to the Trash?"), isPresented: $confirming) {
            Button("Move to Trash (\(model.selectedBytes.formattedBytes))", role: .destructive) {
                Task { await model.trashSelection() }
            }
        } message: {
            Text("You can restore them from the Trash. The space is freed when you empty it.")
        }
        .sheet(item: $model.outcome) { outcome in
            CleanupOutcomeView(outcome: outcome) {
                Task { await model.retryWithAdministrator() }
            }
        }
    }

    private var start: some View {
        VStack(spacing: 14) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("See what takes up space")
                .font(.title2.bold())
            Text("Space Lens measures every folder and shows it as bubbles sized by the space it really uses.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack {
                Button("Scan Home Folder") { model.scanHome() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                Button("Choose Folder…") { chooseFolder() }
            }
            .controlSize(.large)
            .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanning: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Measuring…")
                .font(.headline)
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                VStack(spacing: 6) {
                    Text(model.progress.currentPath ?? " ")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 520)
                    if let started = model.scanStarted {
                        Text(Duration.seconds(Date().timeIntervalSince(started)),
                             format: .time(pattern: .minuteSecond))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button("Cancel", role: .cancel) { model.cancelScan() }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func browser(_ folder: SizeNode) -> some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    BreadcrumbBar(path: model.path) { model.goBack(to: $0) }
                    Spacer()
                    Text(folder.bytes.formattedBytes)
                        .font(.headline.monospacedDigit())
                }
                .padding(12)
                if folder.isAccessDenied, folder.children.isEmpty {
                    FullDiskAccessBanner(unreadableCount: 1)
                        .padding(12)
                }
                BubbleCanvas(folder: folder, revision: model.revision,
                             isSelected: { model.isSelected($0) },
                             onOpen: { model.open($0) },
                             onToggle: { model.toggle($0) })
                    .id(ObjectIdentifier(folder))
            }
            .frame(minWidth: 420)

            VStack(spacing: 0) {
                FolderContentsList(folder: folder, revision: model.revision, model: model)
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
                        .disabled(model.selection.isEmpty || model.phase != .ready)
                }
                .padding(12)
            }
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 420)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.root?.url ?? FileManager.default.homeDirectoryForCurrentUser
        if panel.runModal() == .OK, let url = panel.url {
            model.scan(url, chosenByUser: true)
        }
    }
}
