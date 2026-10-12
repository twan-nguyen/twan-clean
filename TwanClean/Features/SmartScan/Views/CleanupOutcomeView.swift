import SwiftUI

/// Reports what a cleanup freed, what failed and how to finish the rest.
struct CleanupOutcomeView: View {
    let outcome: CleanupOutcome
    let onRetryWithAdministrator: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hasFullDiskAccess = FullDiskAccess.isGranted()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: outcome.failures.isEmpty && outcome.needsAdministrator.isEmpty
                      ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(outcome.failures.isEmpty && outcome.needsAdministrator.isEmpty ? .green : .orange)
                VStack(alignment: .leading) {
                    Text("Freed \(outcome.freedBytes.formattedBytes)")
                        .font(.title2.bold())
                    Text("\(outcome.removedCount) items removed")
                        .foregroundStyle(.secondary)
                }
            }

            if !outcome.needsAdministrator.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(outcome.needsAdministrator.count) items could not be removed without more access")
                        .font(.headline)
                    if hasFullDiskAccess {
                        Text("They belong to macOS or another user. Twan Clean can remove them with your administrator password.")
                            .foregroundStyle(.secondary)
                        Button("Remove with Password…") {
                            dismiss()
                            onRetryWithAdministrator()
                        }
                    } else {
                        Text("Give Twan Clean Full Disk Access first; many of these items only need that. Then clean again.")
                            .foregroundStyle(.secondary)
                        Button("Open Full Disk Access Settings") {
                            FullDiskAccess.openSystemSettings()
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            if !outcome.failures.isEmpty {
                DisclosureGroup("\(outcome.failures.count) items failed") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(outcome.failures) { failure in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(failure.name).font(.callout.bold())
                                    Text(failure.message).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
