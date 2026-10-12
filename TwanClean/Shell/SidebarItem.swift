import Foundation

enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case smartScan
    case spaceLens
    case uninstaller
    case orphans

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .smartScan: "Smart Scan"
        case .spaceLens: "Space Lens"
        case .uninstaller: "App Uninstaller"
        case .orphans: "Orphaned Files"
        }
    }

    var systemImage: String {
        switch self {
        case .smartScan: "sparkles"
        case .spaceLens: "circle.hexagongrid"
        case .uninstaller: "trash.square"
        case .orphans: "questionmark.folder"
        }
    }
}
