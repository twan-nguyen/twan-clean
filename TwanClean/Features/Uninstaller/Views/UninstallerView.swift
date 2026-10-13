import SwiftUI

struct UninstallerView: View {
    @EnvironmentObject private var model: UninstallerViewModel

    var body: some View {
        HSplitView {
            AppListView(model: model)
                .frame(minWidth: 240, idealWidth: 290, maxWidth: 380)
                .disabled(model.phase == .uninstalling)
            Group {
                if let app = model.selectedApp {
                    AppDetailView(app: app, model: model)
                        .id(app.id)
                        .phaseTransition()
                } else {
                    EmptyStateCard(systemImage: "square.grid.2x2.fill", tint: Tint.purple,
                                   title: "Choose an app",
                                   message: "Or in Finder: Services › Uninstall with Twan Clean.")
                        .phaseTransition()
                }
            }
            .animatesPhase(model.selectedApp?.id)
            .frame(minWidth: 400)
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
