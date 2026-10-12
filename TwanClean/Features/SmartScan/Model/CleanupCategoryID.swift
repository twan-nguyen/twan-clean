import SwiftUI

/// The kinds of junk Smart Scan looks for.
enum CleanupCategoryID: String, CaseIterable, Identifiable, Codable, Sendable {
    case systemJunk
    case userCache
    case aiApps
    case mail
    case trash
    case largeOld
    case xcode
    case brew
    case node
    case docker

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .systemJunk: "System Junk"
        case .userCache: "User Cache"
        case .aiApps: "AI Apps"
        case .mail: "Mail Attachments"
        case .trash: "Trash"
        case .largeOld: "Large & Old Files"
        case .xcode: "Xcode Junk"
        case .brew: "Homebrew Cache"
        case .node: "Node Cache"
        case .docker: "Docker Cache"
        }
    }

    /// One short line under the title.
    var summary: LocalizedStringResource {
        switch self {
        case .systemJunk: "Logs and temporary files."
        case .userCache: "Caches apps rebuild."
        case .aiApps: "Ollama and LM Studio caches."
        case .mail: "Attachments Mail downloaded."
        case .trash: "Items in your Trash."
        case .largeOld: "Big files and files untouched for long."
        case .xcode: "Build products, simulators, archives."
        case .brew: "Downloads kept after installs."
        case .node: "npm, Yarn and pnpm caches."
        case .docker: "Docker Desktop logs and caches."
        }
    }

    /// What is worth knowing before cleaning, shown behind an ⓘ.
    var note: LocalizedStringResource? {
        switch self {
        case .aiApps, .mail, .largeOld, .userCache, .systemJunk: noteText
        default: nil
        }
    }

    // Kept non-optional: string extraction misses literals returned as an
    // optional.
    private var noteText: LocalizedStringResource {
        switch self {
        case .aiApps: "Chat history is never selected for you."
        case .mail: "The originals stay on the mail server, so Mail can download them again."
        case .largeOld: "Nothing here is selected for you, and removed files go to the Trash. Set the size and age in Settings."
        case .userCache: "Apps recreate these, so they are deleted rather than moved to the Trash."
        case .systemJunk: "Items macOS or a running app uses, or that need your password, are marked and not selected."
        default: summary
        }
    }

    var systemImage: String {
        switch self {
        case .systemJunk: "gearshape.2.fill"
        case .userCache: "internaldrive.fill"
        case .aiApps: "brain"
        case .mail: "envelope.fill"
        case .trash: "trash.fill"
        case .largeOld: "doc.badge.clock"
        case .xcode: "hammer.fill"
        case .brew: "mug.fill"
        case .node: "shippingbox.fill"
        case .docker: "cube.box.fill"
        }
    }

    /// Each category keeps one colour across the sidebar, charts and lists.
    var tint: Color {
        switch self {
        case .systemJunk: Tint.purple
        case .userCache: Tint.blue
        case .aiApps: Tint.teal
        case .mail: Tint.orange
        case .trash: Tint.red
        case .largeOld: Tint.yellow
        case .xcode: Tint.cyan
        case .brew: Tint.brown
        case .node: Tint.pink
        case .docker: Tint.indigo
        }
    }

    /// Heavy categories walk large trees and are started first so the scan
    /// finishes sooner.
    var isHeavy: Bool {
        switch self {
        case .largeOld, .userCache, .xcode, .systemJunk: true
        default: false
        }
    }

    /// When two categories find the same folder, the one listed first keeps it.
    static let ownershipOrder: [CleanupCategoryID] = [
        .trash, .xcode, .node, .brew, .docker, .aiApps, .mail, .largeOld, .systemJunk, .userCache,
    ]
}
