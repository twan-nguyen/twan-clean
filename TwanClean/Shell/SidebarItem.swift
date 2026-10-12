import SwiftUI

enum SidebarItem: Hashable, Identifiable {
    case smartScan
    case spaceLens
    case uninstaller
    case orphans
    case category(CleanupCategoryID)

    var id: String {
        switch self {
        case .smartScan: "smartScan"
        case .spaceLens: "spaceLens"
        case .uninstaller: "uninstaller"
        case .orphans: "orphans"
        case .category(let category): "category.\(category.rawValue)"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .smartScan: "Smart Scan"
        case .spaceLens: "Space Lens"
        case .uninstaller: "App Uninstaller"
        case .orphans: "Orphaned Files"
        case .category(let category): category.title
        }
    }

    var systemImage: String {
        switch self {
        case .smartScan: "sparkles"
        case .spaceLens: "circle.hexagongrid.fill"
        case .uninstaller: "square.grid.2x2.fill"
        case .orphans: "questionmark.folder.fill"
        case .category(let category): category.systemImage
        }
    }

    var tint: Color {
        switch self {
        case .smartScan: Tint.teal
        case .spaceLens: Tint.cyan
        case .uninstaller: Tint.purple
        case .orphans: Tint.pink
        case .category(let category): category.tint
        }
    }
}
