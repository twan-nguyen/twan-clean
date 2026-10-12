import AppKit
import SwiftUI

// The look is adapted from MClean (MIT, see THIRD_PARTY_NOTICES): coloured
// icon tiles, flat cards with a hairline border, and one gradient call to
// action per screen.

/// The colours the interface uses. Chrome sticks to the brand teal, green for
/// success, orange for warnings and red for destructive actions; the others
/// tell categories apart.
enum Tint {
    static let teal   = Color(red: 0.11, green: 0.62, blue: 0.46)
    static let blue   = Color(red: 0.04, green: 0.52, blue: 1.00)
    static let green  = Color(red: 0.18, green: 0.78, blue: 0.47)
    static let orange = Color(red: 1.00, green: 0.58, blue: 0.04)
    static let purple = Color(red: 0.55, green: 0.32, blue: 0.87)
    static let pink   = Color(red: 1.00, green: 0.30, blue: 0.50)
    static let cyan   = Color(red: 0.30, green: 0.78, blue: 0.95)
    static let red    = Color(red: 1.00, green: 0.27, blue: 0.23)
    static let yellow = Color(red: 0.92, green: 0.66, blue: 0.00)
    static let indigo = Color(red: 0.35, green: 0.34, blue: 0.84)
    static let mint   = Color(red: 0.00, green: 0.78, blue: 0.75)
    static let brown  = Color(red: 0.64, green: 0.52, blue: 0.37)
}

enum TintGradient {
    static var brand: LinearGradient {
        LinearGradient(colors: [Tint.teal, Tint.blue], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var destructive: LinearGradient {
        LinearGradient(colors: [Tint.red, Tint.red.opacity(0.8)], startPoint: .top, endPoint: .bottom)
    }

    static func of(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Appearance

/// Light or dark regardless of the system setting, picked from the toolbar.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    /// Set on the whole app so the Settings window and sheets follow too.
    @MainActor
    func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Three-way appearance switch with a sliding highlight.
struct AppearancePill: View {
    @Binding var selection: AppearanceMode

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.10))
                .frame(width: 28, height: 22)
                .offset(x: CGFloat(AppearanceMode.allCases.firstIndex(of: selection) ?? 0) * 30)
            HStack(spacing: 2) {
                ForEach(AppearanceMode.allCases) { mode in
                    Button {
                        selection = mode
                    } label: {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 22)
                            .foregroundStyle(selection == mode ? Color.primary : .secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(Text(mode.title))
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: selection)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .fixedSize()
    }
}

// MARK: - Surfaces

/// A rounded square with a tinted fill behind an SF Symbol.
struct IconTile: View {
    let systemName: String
    var tint: Color = Tint.teal
    var size: CGFloat = 26
    var corner: CGFloat = 7
    var glow = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(glow ? 0.30 : 0.16), tint.opacity(0.14)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: tint.opacity(glow ? 0.4 : 0), radius: glow ? 5 : 0)
            Image(systemName: systemName)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The card every screen is built from: flat fill, hairline border and a
/// soft shadow.
struct CardSurface<Content: View>: View {
    var padding: CGFloat = 16
    var raised = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(raised ? 0.07 : 0.04), radius: raised ? 10 : 4, y: raised ? 3 : 1)
    }
}

/// Small tinted capsule for a status or a warning next to a name.
struct StatusChip: View {
    let label: String
    var systemImage: String?
    var tint: Color = Tint.teal

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
            }
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(tint.opacity(0.14)))
        .foregroundStyle(tint)
    }
}

/// Bold title above a group of cards.
struct SectionHeader: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .bold))
            .padding(.top, 4)
    }
}

/// Small grey caption in capitals, used above a big number.
struct Eyebrow: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}

/// Soft brand wash behind every screen.
struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(colors: [Tint.teal.opacity(0.07), .clear], startPoint: .topLeading, endPoint: .center)
            RadialGradient(colors: [Tint.blue.opacity(0.04), .clear], center: .topTrailing, startRadius: 0, endRadius: 600)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Controls

/// The one prominent action on a screen: a gradient capsule with a glow.
struct GlowButtonStyle: ButtonStyle {
    var tint: Color = Tint.teal
    var gradient: LinearGradient = TintGradient.brand

    static var destructive: GlowButtonStyle {
        GlowButtonStyle(tint: Tint.red, gradient: TintGradient.destructive)
    }

    func makeBody(configuration: Configuration) -> some View {
        GlowBody(configuration: configuration, tint: tint, gradient: gradient)
    }

    private struct GlowBody: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        let gradient: LinearGradient
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Capsule().fill(gradient))
                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                .shadow(color: tint.opacity(isEnabled ? (hovering ? 0.45 : 0.25) : 0), radius: hovering ? 12 : 7, y: 3)
                .scaleEffect(configuration.isPressed ? 0.97 : (hovering ? 1.02 : 1))
                .opacity(isEnabled ? 1 : 0.45)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onHover { hovering = $0 && isEnabled }
        }
    }
}

/// Quiet capsule for secondary actions next to a glow button.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.08)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .contentShape(Capsule())
    }
}

// MARK: - Gauges

/// Ring showing how full the disk is.
struct UsageRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 14

    @State private var sweep: Double = 0

    private var clamped: Double { max(0, min(1, fraction)) }
    private var stressed: Bool { clamped >= 0.85 }
    private var tint: Color { stressed ? Tint.orange : Tint.teal }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.07), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(tint.opacity(0.45), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .blur(radius: 8)
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(AngularGradient(colors: [tint.opacity(0.8), stressed ? Tint.red : Tint.blue, tint],
                                        center: .center, startAngle: .degrees(-90),
                                        endAngle: .degrees(-90 + 360 * max(sweep, 0.0001))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(clamped, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 34, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(stressed ? Tint.orange : Color.primary)
                Text("USED")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.82)) { sweep = clamped }
        }
        .onChange(of: clamped) { value in
            withAnimation(.spring(response: 1.0, dampingFraction: 0.82)) { sweep = value }
        }
    }
}

/// Spinning ring with a radar sweep while a scan runs. Without a progress
/// value it shows `systemImage` in the middle instead of a percentage.
struct ScanningGauge: View {
    let progress: Double?
    var tint: Color = Tint.teal
    var label: LocalizedStringKey = "SCANNING"
    var systemImage = "magnifyingglass"

    @State private var rotate = false

    var body: some View {
        ZStack {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let angle = t.truncatingRemainder(dividingBy: 3) / 3 * 360
                Circle()
                    .fill(AngularGradient(colors: [tint.opacity(0), tint.opacity(0), tint.opacity(0.22)], center: .center))
                    .rotationEffect(.degrees(angle))
            }
            .padding(12)
            .clipShape(Circle())
            Circle().stroke(Color.primary.opacity(0.07), lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.05, min(0.95, progress ?? 0.3))))
                .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(rotate ? 360 : 0))
                .animation(.linear(duration: progress == nil ? 1.6 : 4).repeatForever(autoreverses: false), value: rotate)
            VStack(spacing: 2) {
                if let progress {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 30, weight: .semibold))
                        .monospacedDigit()
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { rotate = true }
    }
}

/// Card shown while a tool works: a spinning gauge, what is happening and a
/// cancel button.
struct WorkingCard<Detail: View>: View {
    var progress: Double?
    var tint: Color = Tint.teal
    var gaugeLabel: LocalizedStringKey = "SCANNING"
    var systemImage = "magnifyingglass"
    let title: LocalizedStringKey
    var onCancel: (() -> Void)?
    @ViewBuilder var detail: Detail

    var body: some View {
        CardSurface(padding: 24, raised: true) {
            HStack(alignment: .center, spacing: 28) {
                ScanningGauge(progress: progress, tint: tint, label: gaugeLabel, systemImage: systemImage)
                    .frame(width: 150, height: 150)
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                    detail
                    if let onCancel {
                        Button("Cancel", action: onCancel)
                            .buttonStyle(PillButtonStyle())
                            .padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// The path a scan is reading, refreshed ten times a second.
struct LivePathTicker: View {
    let currentPath: () -> String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            Text(verbatim: currentPath().map { ($0 as NSString).abbreviatingWithTildeInPath } ?? " ")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 380, alignment: .leading)
        }
    }
}

/// Rounded progress bar in a gradient.
struct GradientProgressBar: View {
    let progress: Double
    var tint: Color = Tint.teal

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.65)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(8, geo.size.width * CGFloat(max(0, min(1, progress)))))
                    .animation(.easeOut(duration: 0.35), value: progress)
            }
        }
        .frame(height: 8)
    }
}

/// Coloured dot with a caption and value, used under bars and charts.
struct LegendDot: View {
    let color: Color
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 11.5, weight: .semibold))
                    .monospacedDigit()
            }
        }
    }
}

/// Status dot that pulses while something needs attention.
struct PulsingDot: View {
    let tint: Color
    var isPulsing = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            if isPulsing {
                Circle()
                    .stroke(tint.opacity(pulse ? 0 : 0.6), lineWidth: 2)
                    .frame(width: 18, height: 18)
                    .scaleEffect(pulse ? 1.6 : 0.8)
            } else {
                Circle().fill(tint.opacity(0.2)).frame(width: 16, height: 16)
            }
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .shadow(color: tint.opacity(0.6), radius: 3)
        }
        .frame(width: 18, height: 18)
        .onAppear { syncPulse() }
        .onChange(of: isPulsing) { _ in syncPulse() }
    }

    private func syncPulse() {
        guard isPulsing else {
            pulse = false
            return
        }
        withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
    }
}

// MARK: - Screens

/// Start screen of a tool: a big tile, what the tool does and its actions.
struct ToolIntroCard<Actions: View>: View {
    let systemImage: String
    let tint: Color
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder var actions: Actions

    var body: some View {
        CardSurface(padding: 28, raised: true) {
            HStack(alignment: .center, spacing: 24) {
                IconTile(systemName: systemImage, tint: tint, size: 88, corner: 22, glow: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) { actions }
                        .padding(.top, 8)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Centred message for an empty or finished list.
struct EmptyStateCard: View {
    let systemImage: String
    var tint: Color = Tint.green
    let title: LocalizedStringKey
    var message: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 12) {
            IconTile(systemName: systemImage, tint: tint, size: 64, corner: 18, glow: true)
            Text(title).font(.system(size: 17, weight: .semibold))
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Bottom bar of a list screen: what is selected and the action for it.
struct SelectionFooter<Leading: View, Action: View>: View {
    let selectedBytes: Int64
    var isBusy = false
    @ViewBuilder var leading: Leading
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: 10) {
            leading
            Spacer()
            if isBusy { ProgressView().controlSize(.small) }
            VStack(alignment: .trailing, spacing: 0) {
                Eyebrow("Selected")
                Text(selectedBytes.formattedBytes)
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
            }
            action
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

extension SelectionFooter where Leading == EmptyView {
    init(selectedBytes: Int64, isBusy: Bool = false, @ViewBuilder action: () -> Action) {
        self.init(selectedBytes: selectedBytes, isBusy: isBusy, leading: { EmptyView() }, action: action)
    }
}

extension View {
    /// Shows a scrolling list as a card, inset from the window edges.
    func cardList() -> some View {
        scrollContentBackground(.hidden)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
    }
}

/// Checkbox with a tinted fill, keeping the native checkbox for VoiceOver.
struct TintedCheckboxStyle: ToggleStyle {
    var tint: Color = Tint.teal

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(configuration.isOn ? tint : Color.primary.opacity(0.05))
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .strokeBorder(configuration.isOn ? tint : Color.primary.opacity(0.28), lineWidth: 1)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(configuration.isOn ? 1 : 0.3)
                    .opacity(configuration.isOn ? 1 : 0)
            }
            .frame(width: 15, height: 15)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isOn)
            configuration.label
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.checkbox)
        }
    }
}

extension ToggleStyle where Self == TintedCheckboxStyle {
    static var tintedCheckbox: TintedCheckboxStyle { TintedCheckboxStyle() }

    static func tintedCheckbox(_ tint: Color) -> TintedCheckboxStyle { TintedCheckboxStyle(tint: tint) }
}
