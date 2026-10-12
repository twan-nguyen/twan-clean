import SwiftUI

struct ScanProgressView: View {
    let finished: Int
    let total: Int
    let reporter: ScanProgressReporter
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(finished), total: Double(max(total, 1)))
                .frame(maxWidth: 360)
            Text("Scanning… \(finished) of \(total) categories")
                .font(.headline)
                .monospacedDigit()
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                Text(reporter.currentPath ?? " ")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 520)
            }
            Button("Cancel", role: .cancel, action: onCancel)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
