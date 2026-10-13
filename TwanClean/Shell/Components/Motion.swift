import AppKit
import SwiftUI

// Motion shared by the busy states and the transitions between screens. Each
// piece keeps its numbers and text but drops rotation, shimmer and scaling
// when the user asked for reduced motion.

/// Runs `changes` inside an animation, or without one under Reduce Motion.
/// For view models, which cannot read the SwiftUI environment.
@MainActor
func withMotion(_ animation: Animation = .easeInOut(duration: 0.25), _ changes: () -> Void) {
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        changes()
    } else {
        withAnimation(animation, changes)
    }
}

extension View {
    /// Fades and slightly scales this view when it enters or leaves, for the
    /// screens that replace one another as a phase changes. Pair with
    /// `animatesPhase(_:)` on the container.
    func phaseTransition() -> some View {
        modifier(PhaseTransition())
    }

    /// Animates the changes that follow `value`, such as a phase change.
    func animatesPhase<Value: Equatable>(_ value: Value) -> some View {
        modifier(PhaseAnimation(value: value))
    }

    /// Rolls the digits of a number or size when `value` changes. Before
    /// macOS 14 the text simply changes.
    func animatedNumber<Value: Equatable>(_ value: Value) -> some View {
        modifier(AnimatedNumber(value: value))
    }
}

private struct PhaseTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
    }
}

private struct PhaseAnimation<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: value)
    }
}

private struct AnimatedNumber<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 14, *), !reduceMotion {
            content
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.3), value: value)
        } else {
            content
        }
    }
}

/// Time since `since`, refreshed twice a second.
struct ElapsedTimeText: View {
    let since: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            if let since {
                Text(Duration.seconds(max(0, timeline.date.timeIntervalSince(since))),
                     format: .time(pattern: .minuteSecond))
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A bar for work with no measurable end: a highlight sweeps along it, or,
/// under Reduce Motion, it is a still tinted bar.
struct IndeterminateBar: View {
    var tint: Color = Tint.teal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                if reduceMotion {
                    Capsule().fill(tint.opacity(0.3))
                } else {
                    TimelineView(.animation) { timeline in
                        let segment = geo.size.width * 0.35
                        let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                        Capsule()
                            .fill(LinearGradient(colors: [tint.opacity(0.2), tint, tint.opacity(0.2)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: segment)
                            .offset(x: (geo.size.width + segment) * phase - segment)
                    }
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// A grey capsule standing in for text that has not arrived, with a light
/// sweep across it; still under Reduce Motion.
struct ShimmerPlaceholder: View {
    var width: CGFloat?
    var height: CGFloat = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(0.08))
            .frame(width: width, height: height)
            .overlay {
                if !reduceMotion {
                    // Many of these can be on screen at once, so a gentler rate.
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                        GeometryReader { geo in
                            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                            LinearGradient(colors: [.clear, Color.primary.opacity(0.12), .clear],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: geo.size.width * 0.6)
                                .offset(x: geo.size.width * 1.6 * phase - geo.size.width * 0.6)
                        }
                    }
                }
            }
            .clipShape(Capsule())
            .accessibilityHidden(true)
    }
}

/// An SF Symbol that turns while `isSpinning`, and holds still under Reduce
/// Motion.
struct SpinningSymbol: View {
    let systemName: String
    let isSpinning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let spins = isSpinning && !reduceMotion
        TimelineView(.animation(paused: !spins)) { timeline in
            let turn = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
            Image(systemName: systemName)
                .rotationEffect(.degrees(spins ? turn * 360 : 0))
        }
    }
}
