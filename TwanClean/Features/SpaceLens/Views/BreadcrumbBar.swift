import SwiftUI

struct BreadcrumbBar: View {
    let path: [SizeNode]
    let onSelect: (SizeNode) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(path.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    let isLast = index == path.count - 1
                    // A Button gives keyboard focus and the button trait. The
                    // tap gesture inside it stays because buttons inside a
                    // horizontal scroll view miss clicks on macOS 15.
                    Button { onSelect(node) } label: {
                        Text(node.name)
                            .font(.system(size: 12.5, weight: isLast ? .semibold : .regular))
                            .foregroundStyle(isLast ? .primary : .secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(isLast ? Tint.cyan.opacity(0.16) : Color.primary.opacity(0.05)))
                            .contentShape(Capsule())
                            .onTapGesture { onSelect(node) }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
