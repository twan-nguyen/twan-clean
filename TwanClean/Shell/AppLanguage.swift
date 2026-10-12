import Foundation

/// The interface language, applied by macOS when the app starts.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case vietnamese = "vi"
    case english = "en"

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .system: "Same as macOS"
        case .vietnamese: "Tiếng Việt"
        case .english: "English"
        }
    }

    private static let key = "AppleLanguages"

    /// The choice saved for this app, read from its own preferences only.
    static var current: AppLanguage {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        guard let languages = domain?[key] as? [String], let first = languages.first else { return .system }
        return AppLanguage(rawValue: String(first.prefix(2))) ?? .system
    }

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: Self.key)
        } else {
            UserDefaults.standard.set([rawValue], forKey: Self.key)
        }
    }
}
