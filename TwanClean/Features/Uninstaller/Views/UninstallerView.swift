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
                    EmptyStateCard(systemImage: "square.grid.2x2.fill", tint: Tint.purple,
                                   title: "Choose an app to see everything it installed",
                                   message: "Tip: in Finder, Control-click an app and choose Services › Uninstall with Twan Clean.")
                }
            }
            .frame(minWidth: 460)
        }
        .navigationTitle("App Uninstaller")
        .onAppear { model.loadAppsIfNeeded() }
        .sheet(item: $model.outcome) { outcome in
            CleanupOutcomeView(outcome: outcome) {
                Task { await model.retryWithAdministrator(outcome) }
            }
        }
    }
}
