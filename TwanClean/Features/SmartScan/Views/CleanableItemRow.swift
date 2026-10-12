import SwiftUI

struct CleanableItemRow: View {
    let item: CleanableItem
    @Binding var isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Toggle(item.name, isOn: $isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
            Image(systemName: item.isDirectory ? "folder" : "doc")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ForEach(badges, id: \.self) { badge in
                        Text(badge)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
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
                .monospacedDigit()
                .frame(minWidth: 72, alignment: .trailing)
        }
        .contextMenu {
            Button("Show in Finder") { Finder.reveal([item.url]) }
        }
    }

    private var badges: [String] {
        var badges: [String] = []
        if item.requiresAdministrator { badges.append(String(localized: "Needs password")) }
        if item.notes.contains(.appIsRunning) { badges.append(String(localized: "App is running")) }
        if item.notes.contains(.usedByMacOS) { badges.append(String(localized: "Used by macOS")) }
        if item.notes.contains(.personalData) { badges.append(String(localized: "Personal data")) }
        if item.notes.contains(.mayBeNeeded) { badges.append(String(localized: "May be needed")) }
        if item.notes.contains(.partlyUnreadable) { badges.append(String(localized: "Partly unreadable")) }
        return badges
    }
}
