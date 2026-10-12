import Foundation

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
        case .spaceLens: "circle.hexagongrid"
        case .uninstaller: "trash.square"
        case .orphans: "questionmark.folder"
        case .category(let category): category.systemImage
        }
    }
}
