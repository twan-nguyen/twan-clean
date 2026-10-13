import SwiftUI

struct LeftoverGroupList: View {
    let items: [LeftoverItem]
    @ObservedObject var model: UninstallerViewModel

    private var groups: [(LeftoverItem.Group, [LeftoverItem])] {
        LeftoverItem.Group.allCases.compactMap { group in
            let members = items.filter { $0.group == group }
            return members.isEmpty ? nil : (group, members)
        }
    }

    var body: some View {
        List {
            ForEach(groups, id: \.0) { group, members in
                Section {
                    ForEach(members) { item in
                        row(item)
                    }
                } header: {
                    HStack(spacing: 8) {
                        IconTile(systemName: group.systemImage, tint: group.tint, size: 20, corner: 5)
                        Text(group.title)
                            .font(.system(size: 12, weight: .semibold))
                        Text(members.count, format: .number)
                            .font(.system(size: 10.5, weight: .semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                        Spacer()
                        Text(members.reduce(0) { $0 + $1.bytes }.formattedBytes)
                            .font(.system(size: 11.5, weight: .semibold))
                            .monospacedDigit()
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func row(_ item: LeftoverItem) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(get: { model.selection.contains(item.id) },
                                 set: { model.setSelected(item, $0) })) {
                EmptyView()
            }
            .toggleStyle(.tintedCheckbox(item.group.tint))
            .accessibilityLabel(Text(item.name))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    if item.requiresAdministrator {
                        StatusChip(label: String(localized: "Needs password"), tint: Tint.orange)
                    }
                    if item.tier == .developerName || item.tier == .teamIdentifier {
                        StatusChip(label: String(localized: "Matched by developer"), tint: Tint.blue)
                    }
                    if item.mayBelongToAnotherApp {
                        StatusChip(label: String(localized: "May belong to another app"), tint: Tint.yellow)
                    }
                    if item.usedByAnotherCopy {
                        StatusChip(label: String(localized: "Another copy is installed"), tint: Tint.yellow)
                    }
                }
                Text(item.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(item.bytes.formattedBytes)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
        .contextMenu {
            Button("Show in Finder") { Finder.reveal([item.url]) }
        }
    }
}

private extension LeftoverItem.Group {
    var systemImage: String {
        switch self {
        case .application: "app.fill"
        case .supportFiles: "folder.fill"
        case .caches: "internaldrive.fill"
        case .preferences: "slider.horizontal.3"
        case .containers: "shippingbox.fill"
        case .logs: "doc.text.fill"
        case .launchItems: "bolt.fill"
        case .other: "ellipsis.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .application: Tint.blue
        case .supportFiles: Tint.purple
        case .caches: Tint.orange
        case .preferences: Tint.cyan
        case .containers: Tint.pink
        case .logs: Tint.yellow
        case .launchItems: Tint.red
        case .other: Tint.green
        }
    }
}
