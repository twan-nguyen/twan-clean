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
        .confirmationDialog(Text("Move \(model.selection.count) items to the Trash?"), isPresented: $confirming) {
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
    }

    private var start: some View {
        ScrollView {
            ToolIntroCard(systemImage: "circle.hexagongrid.fill", tint: Tint.cyan,
                          title: "See what takes up space",
                          message: "Space Lens measures every folder and shows it as bubbles sized by the space it really uses.") {
                Button { model.scanHome() } label: { Label("Scan Home Folder", systemImage: "house.fill") }
                    .buttonStyle(GlowButtonStyle(tint: Tint.cyan, gradient: TintGradient.of(Tint.cyan)))
                    .keyboardShortcut(.defaultAction)
                Button { chooseFolder() } label: { Label("Choose Folder…", systemImage: "folder") }
                    .buttonStyle(PillButtonStyle())
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
    }

    private var scanning: some View {
        ScrollView {
            WorkingCard(tint: Tint.cyan, gaugeLabel: "MEASURING", systemImage: "circle.hexagongrid.fill",
                        title: "Measuring…", onCancel: { model.cancelScan() }) {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    if let started = model.scanStarted {
                        Text(Duration.seconds(Date().timeIntervalSince(started)), format: .time(pattern: .minuteSecond))
                            .font(.system(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                LivePathTicker { model.progress.currentPath }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
    }

    private func browser(_ folder: SizeNode) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { model.startOver() } label: { Label("New Scan", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(PillButtonStyle())
                    .disabled(model.phase != .ready)
                    .help(Text("Close this map and choose another folder to scan"))
                if model.path.count > 1 {
                    Button { model.goUp() } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(PillButtonStyle())
                        .help(Text("Back"))
                }
                BreadcrumbBar(path: model.path) { model.goBack(to: $0) }
                Spacer()
                Text(folder.bytes.formattedBytes)
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                Button { chooseFolder() } label: { Label("Choose Folder…", systemImage: "folder") }
                    .buttonStyle(PillButtonStyle())
                    .disabled(model.phase == .removing)
                Button { model.rescan() } label: { Label("Scan Again", systemImage: "arrow.clockwise") }
                    .buttonStyle(PillButtonStyle())
                    .disabled(model.phase != .ready)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if folder.isAccessDenied, folder.children.isEmpty {
                FullDiskAccessBanner(unreadableCount: 1)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            HSplitView {
                CardSurface(padding: 8) {
                    BubbleCanvas(folder: folder, revision: model.revision,
                                 isSelected: { model.isSelected($0) },
                                 onOpen: { model.open($0) },
                                 onToggle: { model.toggle($0) })
                        .id(ObjectIdentifier(folder))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.leading, 20)
                .padding(.trailing, 6)
                .padding(.bottom, 12)
                .frame(minWidth: 420)

                FolderContentsList(folder: folder, revision: model.revision, model: model)
                    .cardList()
                    .padding(.leading, 6)
                    .padding(.trailing, 20)
                    .padding(.bottom, 12)
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 440)
            }

            SelectionFooter(selectedBytes: model.selectedBytes, isBusy: model.phase == .removing) {
                Button {
                    confirming = true
                } label: {
                    Label("Move to Trash…", systemImage: "trash")
                }
                .buttonStyle(GlowButtonStyle.destructive)
                .disabled(model.selection.isEmpty || model.phase != .ready)
            }
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
