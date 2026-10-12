import SwiftUI

/// Says that some locations could not be read and offers the fix.
struct FullDiskAccessBanner: View {
    let unreadableCount: Int

    var body: some View {
        HStack(spacing: 10) {
            IconTile(systemName: "lock.shield.fill", tint: Tint.orange, size: 28, corner: 7)
            Text("\(unreadableCount) locations skipped")
                .font(.system(size: 13, weight: .semibold))
            InfoButton("Without Full Disk Access, Twan Clean skips protected folders instead of asking for each one. Grant access, then scan again.")
            Spacer()
            Button("Grant Access") {
                FullDiskAccess.openSystemSettings()
            }
            .buttonStyle(PillButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Tint.orange.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Tint.orange.opacity(0.22), lineWidth: 0.5))
    }
}
