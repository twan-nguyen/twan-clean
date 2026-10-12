import SwiftUI

struct AppListView: View {
    @ObservedObject var model: UninstallerViewModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search apps", text: $model.searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                Picker("Sort", selection: $model.sortBySize) {
                    Text("Name").tag(false)
                    Text("Size").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Button {
                    model.reloadApps()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(model.isLoadingApps)
                .help(Text("Reload"))
            }
            HStack {
                Eyebrow("\(model.visibleApps.count) apps")
                Spacer()
            }
            if model.isLoadingApps && model.apps.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.visibleApps, selection: Binding(
                    get: { model.selectedApp?.id },
                    set: { id in model.select(model.apps.first { $0.id == id }) })) { app in
                    HStack(spacing: 10) {
                        AppIconView(url: app.url, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            if let version = app.version {
                                Text(version)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let bytes = model.sizes[app.id] {
                            Text(bytes.formattedBytes)
                                .font(.system(size: 11.5, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                    .tag(app.id)
                }
                .listStyle(.inset)
                .cardList()
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 14)
    }
}
