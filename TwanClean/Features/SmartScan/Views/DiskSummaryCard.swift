import SwiftUI

struct DiskSummaryCard: View {
    let disk: DiskSpace

    private var usedFraction: Double {
        disk.totalBytes > 0 ? Double(disk.usedBytes) / Double(disk.totalBytes) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Startup Disk", systemImage: "internaldrive")
                    .font(.headline)
                Spacer()
                Text("\(disk.availableBytes.formattedBytes) available of \(disk.totalBytes.formattedBytes)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: usedFraction)
                .tint(usedFraction > 0.9 ? .red : .accentColor)
            if disk.purgeableBytes > 0 {
                Text("macOS can also free \(disk.purgeableBytes.formattedBytes) of purgeable space by itself when it needs room.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
