import Foundation

/// When and how the scheduled scan runs. Stored in a file both the app and
/// the background run read.
struct ScheduleSettings: Codable, Equatable, Sendable {
    enum Frequency: String, Codable, CaseIterable, Identifiable, Sendable {
        case daily
        case weekly
        case monthly

        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .daily: "Every day"
            case .weekly: "Every week"
            case .monthly: "Every month"
            }
        }
    }

    enum Action: String, Codable, CaseIterable, Identifiable, Sendable {
        /// Scan and report what could be freed.
        case notify
        /// Also remove the safe items, then report.
        case clean

        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .notify: "Scan and notify me"
            case .clean: "Scan and clean safe items"
            }
        }
    }

    var isEnabled = false
    var frequency = Frequency.weekly
    /// Local hour of the day, 0–23, from which a due run may start.
    var hour = 10
    var action = Action.notify
    var categories: [CleanupCategoryID] = ScheduleSettings.defaultCategories
    /// Automatic cleaning only happens when at least this much can be freed.
    var minimumBytesToClean: Int64 = 100 * 1_000_000
    var lastRun: Date?

    /// Categories whose items are regenerable. Large files, Mail and the
    /// Trash hold the user's own data and are only scanned when chosen.
    static let defaultCategories: [CleanupCategoryID] = [.systemJunk, .userCache, .aiApps, .xcode, .brew, .node, .docker]

    /// Categories that may be scheduled at all. Large and old files are left
    /// out: they need a person to judge them.
    static let schedulableCategories = CleanupCategoryID.allCases.filter { $0 != .largeOld }

    /// The moment the next run becomes due.
    func nextRun(now: Date, calendar: Calendar = .current) -> Date {
        guard let lastRun else {
            // Never run: due from today's hour on.
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
        }
        let lastDay = calendar.startOfDay(for: lastRun)
        let step: DateComponents = switch frequency {
        case .daily: DateComponents(day: 1)
        case .weekly: DateComponents(day: 7)
        case .monthly: DateComponents(month: 1)
        }
        let nextDay = calendar.date(byAdding: step, to: lastDay) ?? lastDay
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: nextDay) ?? nextDay
    }

    /// Whether a run should happen now. A run missed while the Mac slept
    /// becomes due at the next check after it wakes.
    func isDue(now: Date, calendar: Calendar = .current) -> Bool {
        isEnabled && now >= nextRun(now: now, calendar: calendar)
    }
}

/// What the last scheduled run did, for the menu bar and Settings.
struct ScheduledRunSummary: Codable, Equatable, Sendable {
    let date: Date
    let foundBytes: Int64
    let cleanedBytes: Int64
    let failedCount: Int
    /// Locations skipped because Full Disk Access is missing.
    let lockedCount: Int
}

/// Reads and writes the schedule and the last run's summary.
struct ScheduleStore: Sendable {
    let folder: URL

    init(folder: URL = ScheduleStore.defaultFolder) {
        self.folder = folder
    }

    static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TwanClean", isDirectory: true)
    }

    private var settingsFile: URL { folder.appendingPathComponent("schedule.json") }
    private var summaryFile: URL { folder.appendingPathComponent("last-scheduled-run.json") }

    func loadSettings() -> ScheduleSettings {
        read(ScheduleSettings.self, from: settingsFile) ?? ScheduleSettings()
    }

    func save(_ settings: ScheduleSettings) throws {
        try write(settings, to: settingsFile)
    }

    func loadSummary() -> ScheduledRunSummary? {
        read(ScheduledRunSummary.self, from: summaryFile)
    }

    func save(_ summary: ScheduledRunSummary) throws {
        try write(summary, to: summaryFile)
    }

    private func read<Value: Decodable>(_ type: Value.Type, from file: URL) -> Value? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    private func write<Value: Encodable>(_ value: Value, to file: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: file, options: .atomic)
    }
}
