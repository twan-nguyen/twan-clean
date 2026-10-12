import SwiftUI

struct AppListView: View {
    @ObservedObject var model: UninstallerViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search apps", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                Picker("Sort", selection: $model.sortBySize) {
                    Text("Name").tag(false)
                    Text("Size").tag(true)
                }
                .labelsHidden()
                .fixedSize()
            }
            .padding(10)
            Divider()
            if model.isLoadingApps && model.apps.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.visibleApps, selection: Binding(
                    get: { model.selectedApp?.id },
                    set: { id in model.select(model.apps.first { $0.id == id }) })) { app in
                    HStack(spacing: 10) {
                        AppIconView(url: app.url, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name).lineLimit(1)
                            if let version = app.version {
                                Text(version)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let bytes = model.sizes[app.id] {
                            Text(bytes.formattedBytes)
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(app.id)
                }
                .listStyle(.inset)
            }
        }
    }
}
