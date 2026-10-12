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
                    HStack {
                        Text(group.title)
                        Spacer()
                        Text(members.reduce(0) { $0 + $1.bytes }.formattedBytes)
                            .monospacedDigit()
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func row(_ item: LeftoverItem) -> some View {
        HStack(spacing: 8) {
            Toggle(item.name, isOn: Binding(get: { model.selection.contains(item.id) },
                                            set: { model.setSelected(item, $0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            Image(systemName: item.isDirectory ? "folder" : "doc")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    if item.requiresAdministrator { badge(String(localized: "Needs password")) }
                    if item.tier == .developerName || item.tier == .teamIdentifier {
                        badge(String(localized: "Matched by developer"))
                    }
                    if item.mayBelongToAnotherApp {
                        badge(String(localized: "May belong to another app"))
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
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            Button("Show in Finder") { Finder.reveal([item.url]) }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}
