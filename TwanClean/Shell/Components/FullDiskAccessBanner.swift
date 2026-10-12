import SwiftUI

/// Explains that some locations could not be read and offers the fix.
struct FullDiskAccessBanner: View {
    let unreadableCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Some locations could not be read")
                    .font(.headline)
                Text("Twan Clean could not read \(unreadableCount) locations. Give it Full Disk Access to see everything, then scan again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Open Settings") {
                FullDiskAccess.openSystemSettings()
            }
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
