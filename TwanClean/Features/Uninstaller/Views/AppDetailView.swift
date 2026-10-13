import SwiftUI

struct AppDetailView: View {
    let app: InstalledApp
    @ObservedObject var model: UninstallerViewModel
    @State private var confirming = false
    @State private var askingToQuit = false
    /// The selection the user confirmed, frozen before the app is asked to quit.
    @State private var confirmedItems: [LeftoverItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
            if model.isFindingLeftovers {
                WorkingCard(tint: Tint.purple, gaugeLabel: "SEARCHING", systemImage: "square.grid.2x2.fill",
                            title: "Looking for the app's files…") {
                    ElapsedTimeText(since: model.leftoverSearchStarted)
                    LivePathTicker { model.leftoverProgress.currentPath }
                }
                .padding(.horizontal, 16)
                .phaseTransition()
                Spacer()
            } else if let scan = model.leftovers {
                VStack(alignment: .leading, spacing: 12) {
                    Group {
                        if !scan.lockedLocations.isEmpty {
                            FullDiskAccessBanner(unreadableCount: scan.lockedLocations.count)
                        }
                        if let error = model.leftoverError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Tint.orange)
                        }
                        LeftoverGroupList(items: scan.items, model: model)
                            .cardList()
                            .disabled(model.phase == .uninstalling)
                    }
                    .padding(.horizontal, 16)
                    footer
                }
                .removalOverlay(model.removalProgress, tint: Tint.purple)
                .phaseTransition()
            } else {
                Spacer()
            }
        }
        .animatesPhase(model.isFindingLeftovers)
        .confirmationDialog(Text("Uninstall \(app.name)?"), isPresented: $confirming) {
            Button("Move \(model.selectedItems.count) Items to Trash", role: .destructive) { start() }
        } message: {
            Text("\(model.selectedBytes.formattedBytes) goes to the Trash. Restorable until you empty it.")
        }
        .alert(Text("\(app.name) is running"), isPresented: $askingToQuit) {
            Button("Quit and Uninstall") { Task { await model.uninstall(confirmedItems, of: app) } }
            Button("Force Quit and Uninstall", role: .destructive) {
                Task { await model.uninstall(confirmedItems, of: app, forceQuit: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It must quit first. Force quitting may lose unsaved changes.")
        }
    }

    private var header: some View {
        CardSurface(padding: 18, raised: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    AppIconView(url: app.url, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.system(size: 20, weight: .bold))
                        Text(app.bundleIdentifier)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text(app.url.deletingLastPathComponent().path)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if let scan = model.leftovers {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(scan.items.reduce(0) { $0 + $1.bytes }.formattedBytes)
                                .font(.system(size: 22, weight: .semibold))
                                .monospacedDigit()
                                .animatedNumber(scan.items.reduce(0) { $0 + $1.bytes })
                            Text("\(scan.items.count) items")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                HStack(spacing: 12) {
                    Picker("Search", selection: $model.sensitivity) {
                        ForEach(SearchSensitivity.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(model.phase == .uninstalling)
                    .frame(width: 260)
                    InfoButton(resource: model.sensitivity.summary)
                    Spacer()
                }
            }
        }
    }

    private var footer: some View {
        SelectionFooter(selectedBytes: model.selectedBytes, isBusy: model.phase == .uninstalling) {
            Button {
                confirming = true
            } label: {
                Label("Uninstall…", systemImage: "trash")
            }
            .buttonStyle(GlowButtonStyle.destructive)
            .disabled(model.selectedItems.isEmpty || model.phase != .idle)
        }
    }

    private func start() {
        confirmedItems = model.selectedItems
        if model.isRunning(app) {
            askingToQuit = true
        } else {
            Task { await model.uninstall(confirmedItems, of: app) }
        }
    }
}
