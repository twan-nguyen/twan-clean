import Foundation

/// Apps the uninstaller never offers: parts of macOS, and Xcode, whose
/// leftovers include the user's own developer data. List adapted from
/// MClean (MIT), see THIRD_PARTY_NOTICES.
enum ProtectedApps {
    static let bundleIdentifiers: Set<String> = [
        "com.apple.Safari", "com.apple.finder", "com.apple.AppStore", "com.apple.systempreferences",
        "com.apple.Terminal", "com.apple.ActivityMonitor", "com.apple.dt.Xcode", "com.apple.mail",
        "com.apple.iCal", "com.apple.AddressBook", "com.apple.Preview", "com.apple.TextEdit",
        "com.apple.calculator", "com.apple.MobileSMS", "com.apple.FaceTime", "com.apple.Music",
        "com.apple.TV", "com.apple.Podcasts", "com.apple.News", "com.apple.Maps", "com.apple.Photos",
        "com.apple.Notes", "com.apple.reminders", "com.apple.Stocks", "com.apple.Home", "com.apple.weather",
        "com.apple.clock", "com.apple.Passwords",
    ]

    static func contains(_ bundleIdentifier: String) -> Bool {
        bundleIdentifiers.contains { $0.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }
            || bundleIdentifier.caseInsensitiveCompare(Bundle.main.bundleIdentifier ?? "") == .orderedSame
    }
}
