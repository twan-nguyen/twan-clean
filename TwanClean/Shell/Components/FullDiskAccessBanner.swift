import SwiftUI

/// Explains that some locations could not be read and offers the fix.
struct FullDiskAccessBanner: View {
    let unreadableCount: Int

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemName: "lock.shield.fill", tint: Tint.orange, size: 32, corner: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text("Some locations could not be read")
                    .font(.system(size: 13, weight: .semibold))
                Text("Twan Clean could not read \(unreadableCount) locations. Give it Full Disk Access to see everything, then scan again.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Open Settings") {
                FullDiskAccess.openSystemSettings()
            }
            .buttonStyle(PillButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Tint.orange.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Tint.orange.opacity(0.22), lineWidth: 0.5))
    }
}
