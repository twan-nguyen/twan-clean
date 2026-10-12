import SwiftUI

/// The Smart Scan start card: how full the startup disk is and the scan
/// button.
struct DiskSummaryCard: View {
    let disk: DiskSpace
    let onScan: () -> Void

    private var usedFraction: Double {
        disk.totalBytes > 0 ? Double(disk.usedBytes) / Double(disk.totalBytes) : 0
    }

    var body: some View {
        CardSurface(padding: 24, raised: true) {
            HStack(alignment: .center, spacing: 28) {
                UsageRing(fraction: usedFraction)
                    .frame(width: 150, height: 150)
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Eyebrow("Startup Disk")
                                if usedFraction >= 0.85 {
                                    StatusChip(label: String(localized: "Low space"),
                                               systemImage: "exclamationmark.triangle.fill", tint: Tint.orange)
                                }
                            }
                            Text(disk.availableBytes.formattedBytes)
                                .font(.system(size: 32, weight: .semibold))
                                .monospacedDigit()
                            Text("free of \(disk.totalBytes.formattedBytes)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(action: onScan) {
                            Label("Smart Scan", systemImage: "sparkles")
                        }
                        .buttonStyle(GlowButtonStyle())
                        .keyboardShortcut(.defaultAction)
                    }
                    GradientProgressBar(progress: usedFraction, tint: usedFraction >= 0.85 ? Tint.orange : Tint.teal)
                    HStack(spacing: 16) {
                        LegendDot(color: Tint.teal, label: "Used", value: disk.usedBytes.formattedBytes)
                        LegendDot(color: Color.primary.opacity(0.2), label: "Free", value: disk.availableBytes.formattedBytes)
                        if disk.purgeableBytes > 0 {
                            LegendDot(color: Tint.green, label: "Purgeable", value: disk.purgeableBytes.formattedBytes)
                            InfoButton("Space macOS frees by itself when it needs room, such as iCloud copies and snapshots. No app can clean it.")
                        }
                    }
                }
            }
        }
    }
}
