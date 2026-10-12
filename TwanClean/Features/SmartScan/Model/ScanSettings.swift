import Foundation

/// User preferences for Smart Scan, shared by the app and the scheduled run.
struct ScanSettings: Codable, Equatable, Sendable {
    /// Files at least this big count as large.
    var largeFileMinimumBytes: Int64 = 100 * 1_000_000
    /// Files untouched for this many months count as old...
    var oldFileMonths = 12
    /// ...provided they are at least this big.
    var oldFileMinimumBytes: Int64 = 10 * 1_000_000
    /// Folders the large and old file scan skips.
    var excludedFolders: [String] = []

    static let defaultsKey = "smartScan.settings"

    static func load(from defaults: UserDefaults = .standard) -> ScanSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(ScanSettings.self, from: data) else {
            return ScanSettings()
        }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
