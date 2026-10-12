import SwiftUI

struct AppDetailView: View {
    let app: InstalledApp
    @ObservedObject var model: UninstallerViewModel
    @State private var confirming = false
    @State private var askingToQuit = false
    /// The selection the user confirmed, frozen before the app is asked to quit.
    @State private var confirmedItems: [LeftoverItem] = []

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(20)
            Divider()
            if model.isFindingLeftovers {
                ProgressView("Looking for the app's files…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let scan = model.leftovers {
                if !scan.lockedLocations.isEmpty {
                    FullDiskAccessBanner(unreadableCount: scan.lockedLocations.count)
                        .padding([.horizontal, .top], 12)
                }
                if let error = model.leftoverError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .padding(12)
                }
                LeftoverGroupList(items: scan.items, model: model)
                    .disabled(model.phase == .uninstalling)
                Divider()
                footer
            }
        }
        .confirmationDialog(Text("Uninstall \(app.name)?"), isPresented: $confirming) {
            Button("Move \(model.selectedItems.count) Items to Trash", role: .destructive) { start() }
        } message: {
            Text("The selected items, \(model.selectedBytes.formattedBytes) in total, go to the Trash, where you can still restore them.")
        }
        .alert(Text("\(app.name) is running"), isPresented: $askingToQuit) {
            Button("Quit and Uninstall") { Task { await model.uninstall(confirmedItems, of: app) } }
            Button("Force Quit and Uninstall", role: .destructive) {
                Task { await model.uninstall(confirmedItems, of: app, forceQuit: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Twan Clean needs to quit it first. Unsaved changes in the app may be lost if you force it to quit.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            AppIconView(url: app.url, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.title2.bold())
                Text(app.bundleIdentifier)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(app.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Picker("Search", selection: $model.sensitivity) {
                    ForEach(SearchSensitivity.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(model.phase == .uninstalling)
                .frame(width: 280)
                Text(model.sensitivity.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 280, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Selected: \(model.selectedBytes.formattedBytes)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer()
            if model.phase == .uninstalling {
                ProgressView().controlSize(.small)
            }
            Button("Uninstall…") { confirming = true }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedItems.isEmpty || model.phase != .idle)
        }
        .padding(12)
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
