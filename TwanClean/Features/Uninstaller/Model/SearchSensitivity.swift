import Foundation

/// How broadly the uninstaller looks for an app's files.
enum SearchSensitivity: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Only names exactly equal to the app's identifier or name.
    case strict
    /// Names that contain them, plus related identifiers. The default.
    case enhanced
    /// Also anything named after the developer.
    case deep

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .strict: "Strict"
        case .enhanced: "Enhanced"
        case .deep: "Deep"
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .strict: "Only files named exactly after the app. Finds the least, never guesses."
        case .enhanced: "Also files whose names contain the app's name or identifier. Recommended."
        case .deep: "Also files named after the developer. May include files of the developer's other apps, which are never selected for you."
        }
    }

    static let defaultsKey = "uninstaller.sensitivity"
}
