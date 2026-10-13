import XCTest
@testable import TwanClean

final class ScheduleSettingsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Saigon")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func settings(_ frequency: ScheduleSettings.Frequency, lastRun: Date?) -> ScheduleSettings {
        var settings = ScheduleSettings()
        settings.isEnabled = true
        settings.frequency = frequency
        settings.hour = 10
        settings.lastRun = lastRun
        return settings
    }

    func testDisabledIsNeverDue() {
        var disabled = settings(.daily, lastRun: nil)
        disabled.isEnabled = false
        XCTAssertFalse(disabled.isDue(now: date(13, 23), calendar: calendar))
    }

    func testFirstRunWaitsForTheChosenHour() {
        let first = settings(.weekly, lastRun: nil)
        XCTAssertFalse(first.isDue(now: date(13, 9), calendar: calendar))
        XCTAssertTrue(first.isDue(now: date(13, 10), calendar: calendar))
    }

    func testDailyRunsOncePerDay() {
        let daily = settings(.daily, lastRun: date(13, 10))
        XCTAssertFalse(daily.isDue(now: date(13, 23), calendar: calendar))
        XCTAssertFalse(daily.isDue(now: date(14, 9), calendar: calendar))
        XCTAssertTrue(daily.isDue(now: date(14, 10), calendar: calendar))
    }

    func testMissedRunCatchesUpAfterSleep() {
        let weekly = settings(.weekly, lastRun: date(1, 10))
        XCTAssertTrue(weekly.isDue(now: date(13, 7), calendar: calendar))
    }

    func testWeeklyAndMonthlyIntervals() {
        XCTAssertEqual(settings(.weekly, lastRun: date(1, 15)).nextRun(now: date(2, 0), calendar: calendar), date(8, 10))
        XCTAssertEqual(settings(.monthly, lastRun: date(31, 15)).nextRun(now: date(31, 16), calendar: calendar),
                       date(30, 10, month: 11))
    }

    func testLastRunInTheFutureIsTreatedAsDue() {
        let wrongClock = settings(.weekly, lastRun: date(30, 10))
        XCTAssertTrue(wrongClock.isDue(now: date(13, 11), calendar: calendar))
        XCTAssertEqual(wrongClock.nextRun(now: date(13, 11), calendar: calendar), date(13, 10))
    }

    func testUpcomingRunIsNeverInThePast() {
        // Never run and today's hour has passed: a run is already due.
        XCTAssertNil(settings(.weekly, lastRun: nil).upcomingRun(now: date(13, 15), calendar: calendar))
        XCTAssertEqual(settings(.weekly, lastRun: nil).upcomingRun(now: date(13, 9), calendar: calendar), date(13, 10))
        // Missed while the Mac slept.
        XCTAssertNil(settings(.weekly, lastRun: date(1, 10)).upcomingRun(now: date(13, 7), calendar: calendar))
        // A monthly run is a date away, not just a weekday.
        XCTAssertEqual(settings(.monthly, lastRun: date(5, 10)).upcomingRun(now: date(13, 7), calendar: calendar),
                       date(5, 10, month: 11))
    }

    func testLargeFilesCanNeverBeScheduled() {
        XCTAssertFalse(ScheduleSettings.schedulableCategories.contains(.largeOld))
        XCTAssertFalse(ScheduleSettings.defaultCategories.contains(.largeOld))
    }

    func testStoreRoundTrips() throws {
        let tree = try TemporaryTree()
        let store = ScheduleStore(folder: tree.url("store"))
        var saved = settings(.monthly, lastRun: date(5, 10))
        saved.categories = [.xcode]
        try store.save(saved)
        XCTAssertEqual(store.loadSettings(), saved)
        XCTAssertNil(store.loadSummary())
    }

    func testMissingFileIsTheDefaultScheduleButDamagedFileIsAnError() throws {
        let tree = try TemporaryTree()
        let store = ScheduleStore(folder: tree.url("store"))
        XCTAssertEqual(try store.loadSettingsChecked(), ScheduleSettings())

        try tree.makeDirectory("store")
        try Data("{ not json".utf8).write(to: tree.url("store/schedule.json"))
        XCTAssertThrowsError(try store.loadSettingsChecked())
    }

    func testQuarantineKeepsTheDamagedFileAndFreesTheName() throws {
        let tree = try TemporaryTree()
        let store = ScheduleStore(folder: tree.url("store"))
        try tree.makeDirectory("store")
        try Data("{ not json".utf8).write(to: tree.url("store/schedule.json"))

        let moved = try XCTUnwrap(store.quarantineSettings())

        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "{ not json")
        XCTAssertFalse(tree.exists(tree.url("store/schedule.json")))
        XCTAssertEqual(try store.loadSettingsChecked(), ScheduleSettings())
    }

    func testUnknownCategoryAndMissingFieldsDoNotTurnTheScheduleOff() throws {
        let tree = try TemporaryTree()
        try tree.makeDirectory("store")
        let json = """
        {"isEnabled": true, "frequency": "daily", "categories": ["xcode", "someFutureCategory", "node"]}
        """
        try Data(json.utf8).write(to: tree.url("store/schedule.json"))

        let loaded = try ScheduleStore(folder: tree.url("store")).loadSettingsChecked()

        XCTAssertTrue(loaded.isEnabled)
        XCTAssertEqual(loaded.frequency, .daily)
        XCTAssertEqual(loaded.categories, [.xcode, .node])
        XCTAssertEqual(loaded.hour, ScheduleSettings().hour)
    }
}
