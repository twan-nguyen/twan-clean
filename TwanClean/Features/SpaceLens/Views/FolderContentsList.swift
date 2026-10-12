import SwiftUI

/// The open folder's items as a list, with checkboxes for removal.
struct FolderContentsList: View {
    let folder: SizeNode
    let revision: Int
    @ObservedObject var model: SpaceLensViewModel

    var body: some View {
        List {
            ForEach(folder.children) { node in
                HStack(spacing: 8) {
                    Toggle(isOn: Binding(get: { model.isSelected(node) }, set: { _ in model.toggle(node) })) {
                        EmptyView()
                    }
                    .toggleStyle(.tintedCheckbox(Tint.cyan))
                    .accessibilityLabel(Text(node.name))
                    IconTile(systemName: icon(for: node), tint: node.isAccessDenied ? Tint.orange : Tint.cyan,
                             size: 22, corner: 6)
                    Text(node.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(node.bytes.formattedBytes)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 1)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.open(node) }
                .contextMenu {
                    if node.isFolder, !node.children.isEmpty {
                        Button("Open") { model.open(node) }
                    }
                    Button("Show in Finder") { Finder.reveal([node.url]) }
                }
            }
            if folder.prunedCount > 0 {
                HStack {
                    Text("\(folder.prunedCount) smaller items")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(folder.prunedBytes.formattedBytes)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
    }

    private func icon(for node: SizeNode) -> String {
        if node.isAccessDenied { return "lock.fill" }
        switch node.kind {
        case .folder: return "folder.fill"
        case .package: return "shippingbox.fill"
        case .file: return "doc.fill"
        case .symlink: return "arrow.turn.up.right"
        }
    }
}
