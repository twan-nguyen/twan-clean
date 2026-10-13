import SwiftUI

extension RemovalProgress.Stage {
    var title: LocalizedStringKey {
        switch self {
        case .stoppingServices: "Stopping background services…"
        case .quittingApp(let name): "Quitting \(name)…"
        case .cleaning: "Cleaning…"
        case .movingToTrash: "Moving to the Trash…"
        case .waitingForPassword: "Waiting for your password…"
        }
    }

    var gaugeLabel: LocalizedStringKey {
        switch self {
        case .stoppingServices: "STOPPING"
        case .quittingApp: "QUITTING"
        case .cleaning: "CLEANING"
        case .movingToTrash: "REMOVING"
        case .waitingForPassword: "WAITING"
        }
    }

    var systemImage: String {
        switch self {
        case .stoppingServices: "gearshape.2.fill"
        case .quittingApp: "power"
        case .cleaning: "sparkles"
        case .movingToTrash: "trash.fill"
        case .waitingForPassword: "lock.fill"
        }
    }
}

/// What a removal is doing: its stage, how many items are done, the item it
/// is on and a bar. The one card Smart Scan, the Uninstaller, Space Lens and
/// Orphaned Files share.
struct RemovalProgressCard: View {
    let progress: RemovalProgress
    var tint: Color = Tint.teal

    var body: some View {
        WorkingCard(progress: progress.fraction, tint: tint, gaugeLabel: progress.stage.gaugeLabel,
                    systemImage: progress.stage.systemImage, title: progress.stage.title) {
            detail
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private var detail: some View {
        if let fraction = progress.fraction {
            Text("\(progress.completed) of \(progress.total)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            GradientProgressBar(progress: fraction, tint: tint)
                .frame(maxWidth: 340)
            // A blank line keeps the card from changing height as names come and go.
            Text(verbatim: progress.currentName ?? " ")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 380, alignment: .leading)
        } else {
            if progress.stage == .waitingForPassword {
                HStack(spacing: 8) {
                    PulsingDot(tint: Tint.orange, isPulsing: true)
                    Text("Enter your password in the macOS prompt to continue.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            IndeterminateBar(tint: tint)
                .frame(maxWidth: 340)
        }
    }
}

private struct RemovalOverlay: ViewModifier {
    let progress: RemovalProgress?
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if let progress {
                    ZStack {
                        // Catches clicks too, so nothing behind it is reachable.
                        Rectangle().fill(.ultraThinMaterial)
                        RemovalProgressCard(progress: progress, tint: tint)
                            .frame(maxWidth: 560)
                            .padding(24)
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: progress != nil)
    }
}

extension View {
    /// Covers this view with the removal's progress card while one runs. No
    /// sheet: the screen stays where it is, and the controls under the card
    /// are disabled by the screens as before.
    func removalOverlay(_ progress: RemovalProgress?, tint: Color = Tint.teal) -> some View {
        modifier(RemovalOverlay(progress: progress, tint: tint))
    }
}
