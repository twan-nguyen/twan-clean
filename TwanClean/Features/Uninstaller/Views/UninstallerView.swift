import SwiftUI

struct UninstallerView: View {
    @EnvironmentObject private var model: UninstallerViewModel

    var body: some View {
        HSplitView {
            AppListView(model: model)
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
                .disabled(model.phase == .uninstalling)
            Group {
                if let app = model.selectedApp {
                    AppDetailView(app: app, model: model)
                        .id(app.id)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "trash.square")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Choose an app to see everything it installed")
                            .foregroundStyle(.secondary)
                        Text("Tip: in Finder, Control-click an app and choose Services › Uninstall with Twan Clean.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 460)
        }
        .navigationTitle("App Uninstaller")
        .toolbar {
            ToolbarItem {
                Button {
                    model.reloadApps()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear { model.loadAppsIfNeeded() }
        .sheet(item: $model.outcome) { outcome in
            CleanupOutcomeView(outcome: outcome) {
                Task { await model.retryWithAdministrator(outcome) }
            }
        }
    }
}
