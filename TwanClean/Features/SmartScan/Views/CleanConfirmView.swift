import SwiftUI

/// Spells out what cleaning will do before anything is removed.
struct CleanConfirmView: View {
    let items: [CleanableItem]
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var deleted: [CleanableItem] { items.filter { $0.purpose.mode == .delete } }
    private var trashed: [CleanableItem] { items.filter { $0.purpose.mode == .trash } }
    private var needPassword: Int { items.filter(\.requiresAdministrator).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clean \(items.reduce(0) { $0 + $1.bytes }.formattedBytes)?")
                .font(.title2.bold())

            if !deleted.isEmpty {
                summaryRow(icon: "xmark.bin", tint: .red,
                           title: String(localized: "Delete permanently: \(deleted.reduce(0) { $0 + $1.bytes }.formattedBytes)"),
                           detail: String(localized: "\(deleted.count) caches, logs and temporary items. Apps recreate them when needed."))
            }
            if !trashed.isEmpty {
                summaryRow(icon: "trash", tint: .accentColor,
                           title: String(localized: "Move to Trash: \(trashed.reduce(0) { $0 + $1.bytes }.formattedBytes)"),
                           detail: String(localized: "\(trashed.count) items you can still restore from the Trash. Space is freed when you empty it."))
            }
            if needPassword > 0 {
                summaryRow(icon: "lock", tint: .orange,
                           title: String(localized: "\(needPassword) items need your password"),
                           detail: String(localized: "Twan Clean will ask for it after removing everything else."))
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Clean") {
                    dismiss()
                    onConfirm()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func summaryRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
