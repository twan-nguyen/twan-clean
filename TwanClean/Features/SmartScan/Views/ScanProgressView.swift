import SwiftUI

/// Card shown while Smart Scan runs.
struct ScanProgressView: View {
    let finished: Int
    let total: Int
    let reporter: ScanProgressReporter
    let onCancel: () -> Void

    private var progress: Double { Double(finished) / Double(max(total, 1)) }

    var body: some View {
        WorkingCard(progress: progress, title: "Scanning your Mac", onCancel: onCancel) {
            Text("\(finished) of \(total) categories done")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            GradientProgressBar(progress: progress)
                .frame(maxWidth: 340)
            LivePathTicker { reporter.currentPath }
        }
    }
}
