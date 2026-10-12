import Foundation

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

    var summary: LocalizedStringResource {
        switch self {
        case .systemJunk: "Logs and temporary files left by macOS and apps."
        case .userCache: "Cached data apps rebuild when they need it."
        case .aiApps: "Logs and caches from Ollama and LM Studio. Chat history is never selected for you."
        case .mail: "Attachments Mail downloaded to show you; the originals stay on the mail server."
        case .trash: "Items already in your Trash."
        case .largeOld: "Big files, and old files you have not touched in a long time. Nothing here is selected for you, and removed files go to the Trash."
        case .xcode: "Build products, simulator caches and archives from Xcode."
        case .brew: "Downloads Homebrew keeps after installing packages."
        case .node: "Package caches from npm, Yarn and pnpm."
        case .docker: "Docker Desktop logs and caches."
        }
    }

    var systemImage: String {
        switch self {
        case .systemJunk: "gearshape.2"
        case .userCache: "internaldrive"
        case .aiApps: "brain"
        case .mail: "envelope"
        case .trash: "trash"
        case .largeOld: "doc.badge.clock"
        case .xcode: "hammer"
        case .brew: "mug"
        case .node: "shippingbox"
        case .docker: "cube.box"
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
