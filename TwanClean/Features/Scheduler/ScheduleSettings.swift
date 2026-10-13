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

    init() {}

    private enum CodingKeys: String, CodingKey {
        case isEnabled, frequency, hour, action, categories, minimumBytesToClean, lastRun
    }

    /// Fields missing from an older file keep their default, and a category
    /// a later version no longer has is dropped, so neither turns the whole
    /// schedule off.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ScheduleSettings()
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled
        frequency = try values.decodeIfPresent(Frequency.self, forKey: .frequency) ?? defaults.frequency
        hour = try values.decodeIfPresent(Int.self, forKey: .hour) ?? defaults.hour
        action = try values.decodeIfPresent(Action.self, forKey: .action) ?? defaults.action
        categories = try values.decodeIfPresent([String].self, forKey: .categories)?
            .compactMap(CleanupCategoryID.init(rawValue:)) ?? defaults.categories
        minimumBytesToClean = try values.decodeIfPresent(Int64.self, forKey: .minimumBytesToClean)
            ?? defaults.minimumBytesToClean
        lastRun = try values.decodeIfPresent(Date.self, forKey: .lastRun)
    }

    /// Categories whose items are regenerable. Large files, Mail and the
    /// Trash hold the user's own data and are only scanned when chosen.
    static let defaultCategories: [CleanupCategoryID] = [.systemJunk, .userCache, .aiApps, .xcode, .brew, .node, .docker]

    /// Categories that may be scheduled at all. Large and old files are left
    /// out: they need a person to judge them.
    static let schedulableCategories = CleanupCategoryID.allCases.filter { $0 != .largeOld }

    /// The moment the next run becomes due.
    func nextRun(now: Date, calendar: Calendar = .current) -> Date {
        // A last run in the future means the clock was wrong when it was
        // recorded; trusting it would hold the schedule back until then.
        guard let lastRun, lastRun <= now else {
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

    /// When the next run will start, for display. Nil when a run is already
    /// due: it starts at the next hourly check, so no time in the past is shown.
    func upcomingRun(now: Date, calendar: Calendar = .current) -> Date? {
        let next = nextRun(now: now, calendar: calendar)
        return next > now ? next : nil
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

    /// The saved schedule, or the default one when none was saved yet. Throws
    /// when a file exists but cannot be read, so a caller never mistakes a
    /// damaged schedule for a new one.
    func loadSettingsChecked() throws -> ScheduleSettings {
        guard FileManager.default.fileExists(atPath: settingsFile.path) else { return ScheduleSettings() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ScheduleSettings.self, from: Data(contentsOf: settingsFile))
    }

    func loadSettings() -> ScheduleSettings {
        (try? loadSettingsChecked()) ?? ScheduleSettings()
    }

    /// Sets a damaged schedule file aside, keeping it for the user, so the
    /// next save does not overwrite it. Returns where it went.
    @discardableResult
    func quarantineSettings() -> URL? {
        let destination = folder.appendingPathComponent("schedule.json.damaged")
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: settingsFile, to: destination)
            return destination
        } catch {
            return nil
        }
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
