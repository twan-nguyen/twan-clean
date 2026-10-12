import SwiftUI

/// The bubble map of one folder: each child is a circle whose area matches
/// its size. Click a folder to open it, click a file to select it.
struct BubbleCanvas: View {
    struct Bubble: Identifiable {
        enum Content {
            case node(SizeNode)
            /// Everything too small to draw on its own.
            case others(bytes: Int64, count: Int)
        }

        let id: Int
        let content: Content
        let frame: CGRect

        var bytes: Int64 {
            switch content {
            case .node(let node): node.bytes
            case .others(let bytes, _): bytes
            }
        }

        func contains(_ point: CGPoint) -> Bool {
            hypot(point.x - frame.midX, point.y - frame.midY) <= frame.width / 2
        }
    }

    static let maximumBubbles = 24

    let folder: SizeNode
    let revision: Int
    let isSelected: (SizeNode) -> Bool
    let onOpen: (SizeNode) -> Void
    let onToggle: (SizeNode) -> Void

    @State private var hovered: Int?

    var body: some View {
        GeometryReader { proxy in
            let bubbles = Self.bubbles(for: folder, in: proxy.size)
            Canvas { context, _ in
                for bubble in bubbles {
                    draw(bubble, in: &context, highlighted: bubble.id == hovered)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hovered = bubbles.first { $0.contains(point) }?.id
                case .ended: hovered = nil
                }
            }
            .gesture(SpatialTapGesture().onEnded { value in
                guard let bubble = bubbles.first(where: { $0.contains(value.location) }),
                      case .node(let node) = bubble.content else { return }
                if node.isFolder, !node.children.isEmpty { onOpen(node) } else { onToggle(node) }
            })
            .contextMenu {
                if let id = hovered, let bubble = bubbles.first(where: { $0.id == id }), case .node(let node) = bubble.content {
                    Button(isSelected(node) ? "Deselect" : "Select") { onToggle(node) }
                    Button("Show in Finder") { Finder.reveal([node.url]) }
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let id = hovered, let bubble = bubbles.first(where: { $0.id == id }) {
                    HoverCaption(bubble: bubble)
                        .padding(10)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(folder.name))
    }

    static func bubbles(for folder: SizeNode, in size: CGSize) -> [Bubble] {
        let shown = Array(folder.children.prefix(maximumBubbles))
        let hiddenBytes = folder.children.dropFirst(maximumBubbles).reduce(folder.prunedBytes) { $0 + $1.bytes }
        let hiddenCount = folder.children.count - shown.count + folder.prunedCount
        var contents = shown.map(Bubble.Content.node)
        var sizes = shown.map(\.bytes)
        if hiddenBytes > 0 {
            contents.append(.others(bytes: hiddenBytes, count: hiddenCount))
            sizes.append(hiddenBytes)
        }
        let frames = CirclePacker.pack(sizes, in: size)
        return zip(contents, frames).enumerated().map { Bubble(id: $0.offset, content: $0.element.0, frame: $0.element.1) }
    }

    private func draw(_ bubble: Bubble, in context: inout GraphicsContext, highlighted: Bool) {
        let circle = Path(ellipseIn: bubble.frame)
        let color = fill(for: bubble)
        context.fill(circle, with: .linearGradient(
            Gradient(colors: [color.opacity(highlighted ? 0.7 : 0.55), color.opacity(highlighted ? 0.5 : 0.32)]),
            startPoint: CGPoint(x: bubble.frame.midX, y: bubble.frame.minY),
            endPoint: CGPoint(x: bubble.frame.midX, y: bubble.frame.maxY)))
        let selected: Bool = if case .node(let node) = bubble.content { isSelected(node) } else { false }
        context.stroke(circle, with: .color(selected ? Tint.blue : color.opacity(highlighted ? 1 : 0.7)),
                       lineWidth: selected ? 3 : 1)

        guard bubble.frame.width > 56 else { return }
        let title: String = switch bubble.content {
        case .node(let node): node.name
        case .others: String(localized: "Other")
        }
        // Two centred lines, the name cut short to fit inside the circle.
        let fontSize = min(14, max(10, bubble.frame.width / 9))
        let name = context.resolve(Text(verbatim: title)
            .font(.system(size: fontSize, weight: .semibold)).foregroundColor(.primary))
        let size = context.resolve(Text(verbatim: bubble.bytes.formattedBytes)
            .font(.system(size: fontSize - 1)).foregroundColor(.secondary))
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        let nameSize = name.measure(in: unbounded)
        let sizeSize = size.measure(in: unbounded)
        let nameWidth = min(nameSize.width, bubble.frame.width * 0.72)
        let top = bubble.frame.midY - (nameSize.height + sizeSize.height) / 2
        context.draw(name, in: CGRect(x: bubble.frame.midX - nameWidth / 2, y: top,
                                      width: nameWidth, height: nameSize.height))
        context.draw(size, in: CGRect(x: bubble.frame.midX - sizeSize.width / 2, y: top + nameSize.height,
                                      width: sizeSize.width, height: sizeSize.height))
    }

    /// Folders cycle through the palette so neighbours stand apart; files
    /// stay grey. Orange is kept for folders that could not be read.
    private static let palette = [Tint.cyan, Tint.blue, Tint.purple, Tint.pink,
                                  Tint.green, Tint.teal, Tint.indigo, Tint.mint]

    private func fill(for bubble: Bubble) -> Color {
        guard case .node(let node) = bubble.content else { return .gray }
        if node.isAccessDenied { return Tint.orange }
        switch node.kind {
        case .folder, .package: return Self.palette[bubble.id % Self.palette.count]
        case .file, .symlink: return .gray
        }
    }
}

private struct HoverCaption: View {
    let bubble: BubbleCanvas.Bubble

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch bubble.content {
            case .node(let node):
                Text(node.name).font(.headline)
                if node.isAccessDenied {
                    Label("Some contents could not be read", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            case .others(_, let count):
                Text("\(count) smaller items").font(.headline)
            }
            Text(bubble.bytes.formattedBytes)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
