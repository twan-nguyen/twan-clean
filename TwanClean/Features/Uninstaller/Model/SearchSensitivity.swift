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
        case .strict: "Strict: only files named exactly after the app. Finds the least, never guesses."
        case .enhanced: "Enhanced (recommended): also files whose names contain the app's name or identifier."
        case .deep: "Deep: also files named after the developer. Files that may belong to the developer's other apps are never selected for you."
        }
    }

    static let defaultsKey = "uninstaller.sensitivity"
}
