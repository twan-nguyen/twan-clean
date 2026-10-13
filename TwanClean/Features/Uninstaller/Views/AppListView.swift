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
                    SpinningSymbol(systemName: "arrow.clockwise", isSpinning: isBusy)
                }
                .buttonStyle(.borderless)
                .disabled(model.isLoadingApps)
                .accessibilityLabel(Text("Reload"))
                .help(Text("Reload"))
            }
            HStack(spacing: 8) {
                Eyebrow("\(model.visibleApps.count) apps")
                    .animatedNumber(model.visibleApps.count)
                Spacer()
                // Words as well as the turning arrow, which stands still
                // under Reduce Motion.
                if model.isLoadingApps {
                    Text("Loading apps…").font(.caption).foregroundStyle(.secondary)
                } else if model.isMeasuringSizes {
                    Text("Measuring sizes…").font(.caption).foregroundStyle(.secondary)
                }
            }
            .animatesPhase(isBusy)
            if showsSkeleton {
                AppListSkeleton()
                    .cardList()
                    .transition(.opacity)
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
                        } else if model.isMeasuringSizes {
                            ShimmerPlaceholder(width: 44, height: 9)
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
        .animatesPhase(showsSkeleton)
    }

    private var showsSkeleton: Bool { model.isLoadingApps && model.apps.isEmpty }
    private var isBusy: Bool { model.isLoadingApps || model.isMeasuringSizes }
}

/// Rows with grey stand-ins for the icon, name and size, shown while the
/// first list of apps loads.
private struct AppListSkeleton: View {
    private static let rows = 9

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<Self.rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ShimmerPlaceholder(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 5) {
                        ShimmerPlaceholder(width: CGFloat(90 + (row * 37) % 60), height: 10)
                        ShimmerPlaceholder(width: 40, height: 8)
                    }
                    Spacer()
                    ShimmerPlaceholder(width: 44, height: 9)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading apps…"))
    }
}
