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
            HStack(spacing: 12) {
                IconTile(systemName: "sparkles", tint: Tint.teal, size: 40, corner: 10, glow: true)
                Text("Clean \(items.reduce(0) { $0 + $1.bytes }.formattedBytes)?")
                    .font(.system(size: 20, weight: .bold))
            }

            if !deleted.isEmpty {
                summaryRow(icon: "xmark.bin.fill", tint: Tint.red,
                           title: String(localized: "Delete permanently: \(deleted.reduce(0) { $0 + $1.bytes }.formattedBytes)"),
                           detail: String(localized: "\(deleted.count) caches and logs. Apps recreate them."))
            }
            if !trashed.isEmpty {
                summaryRow(icon: "trash.fill", tint: Tint.teal,
                           title: String(localized: "Move to Trash: \(trashed.reduce(0) { $0 + $1.bytes }.formattedBytes)"),
                           detail: String(localized: "\(trashed.count) items. Restorable until you empty the Trash."))
            }
            if needPassword > 0 {
                summaryRow(icon: "lock.fill", tint: Tint.orange,
                           title: String(localized: "\(needPassword) items need your password"),
                           detail: String(localized: "Asked for after everything else is removed."))
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Clean") {
                    dismiss()
                    onConfirm()
                }
                .buttonStyle(GlowButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func summaryRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(systemName: icon, tint: tint, size: 28, corner: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
