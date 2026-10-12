import SwiftUI

struct CleanableItemRow: View {
    let item: CleanableItem
    @Binding var isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $isSelected) { EmptyView() }
                .toggleStyle(.tintedCheckbox(item.category.tint))
                .accessibilityLabel(Text(item.name))
            IconTile(systemName: item.isDirectory ? "folder.fill" : "doc.fill",
                     tint: item.category.tint, size: 24, corner: 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    let chips = badges
                    ForEach(chips.indices, id: \.self) { index in
                        StatusChip(label: chips[index].text, tint: chips[index].tint)
                    }
                }
                Text(item.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if item.category == .largeOld, let date = item.lastModified {
                Text(date, format: .dateTime.year().month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(item.bytes.formattedBytes)
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Show in Finder") { Finder.reveal([item.url]) }
        }
    }

    private var badges: [(text: String, tint: Color)] {
        var badges: [(text: String, tint: Color)] = []
        if item.requiresAdministrator { badges.append((String(localized: "Needs password"), Tint.orange)) }
        if item.notes.contains(.appIsRunning) { badges.append((String(localized: "App is running"), Tint.blue)) }
        if item.notes.contains(.usedByMacOS) { badges.append((String(localized: "Used by macOS"), Tint.purple)) }
        if item.notes.contains(.personalData) { badges.append((String(localized: "Personal data"), Tint.red)) }
        if item.notes.contains(.mayBeNeeded) { badges.append((String(localized: "May be needed"), Tint.yellow)) }
        if item.notes.contains(.partlyUnreadable) { badges.append((String(localized: "Partly unreadable"), Tint.orange)) }
        return badges
    }
}
