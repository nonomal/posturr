import XCTest
@testable import DorsoCore

final class AnalyticsManagerExtendedTests: XCTestCase {

    // MARK: - Test Helpers

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        let cal = calendar
        let components = DateComponents(
            calendar: cal,
            timeZone: cal.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        return cal.date(from: components)!
    }

    private func makeTempFileURL() -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return tmpDir.appendingPathComponent("analytics.json")
    }

    private func makeManager(
        fileURL: URL? = nil,
        now: @escaping () -> Date,
        queue: DispatchQueue? = nil
    ) -> (AnalyticsManager, DispatchQueue, URL) {
        let url = fileURL ?? makeTempFileURL()
        let q = queue ?? DispatchQueue(label: "test.analytics.\(UUID().uuidString)")
        let manager = AnalyticsManager(
            fileURL: url,
            calendar: calendar,
            now: now,
            persistenceQueue: q
        )
        return (manager, q, url)
    }

    // MARK: - trackTime Tests

    func testTrackNonSlouchingTimeIncrementsOnlyTotalSeconds() {
        let date = makeDate(2026, 2, 5)
        let (manager, _, _) = makeManager(now: { date })

        manager.trackTime(interval: 10, isSlouching: false)

        XCTAssertEqual(manager.todayStats.totalSeconds, 10, accuracy: 0.0001)
        XCTAssertEqual(manager.todayStats.slouchSeconds, 0, accuracy: 0.0001)
    }

    func testTrackSlouchingTimeIncrementsBothCounters() {
        let date = makeDate(2026, 2, 5)
        let (manager, _, _) = makeManager(now: { date })

        manager.trackTime(interval: 10, isSlouching: true)

        XCTAssertEqual(manager.todayStats.totalSeconds, 10, accuracy: 0.0001)
        XCTAssertEqual(manager.todayStats.slouchSeconds, 10, accuracy: 0.0001)
    }

    func testMultipleTrackTimeCallsAccumulate() {
        let date = makeDate(2026, 2, 5)
        let (manager, _, _) = makeManager(now: { date })

        manager.trackTime(interval: 5, isSlouching: false)
        manager.trackTime(interval: 3, isSlouching: true)
        manager.trackTime(interval: 7, isSlouching: false)

        XCTAssertEqual(manager.todayStats.totalSeconds, 15, accuracy: 0.0001)
        XCTAssertEqual(manager.todayStats.slouchSeconds, 3, accuracy: 0.0001)
    }

    // MARK: - recordSlouchEvent Tests

    func testRecordSlouchEventIncrementsCount() {
        let date = makeDate(2026, 2, 5)
        let (manager, queue, _) = makeManager(now: { date })

        manager.recordSlouchEvent()
        queue.sync {}

        XCTAssertEqual(manager.todayStats.slouchCount, 1)
    }

    func testMultipleRecordSlouchEventsIncrementCorrectly() {
        let date = makeDate(2026, 2, 5)
        let (manager, queue, _) = makeManager(now: { date })

        manager.recordSlouchEvent()
        manager.recordSlouchEvent()
        manager.recordSlouchEvent()
        queue.sync {}

        XCTAssertEqual(manager.todayStats.slouchCount, 3)
    }

    // MARK: - getLast7Days Tests

    func testGetLast7DaysReturns7Entries() {
        let date = makeDate(2026, 2, 5)
        let (manager, _, _) = makeManager(now: { date })

        let days = manager.getLast7Days()
        XCTAssertEqual(days.count, 7)
    }

    func testGetLast7DaysIsChronological() {
        let date = makeDate(2026, 2, 5)
        let cal = calendar
        let (manager, _, _) = makeManager(now: { date })

        let days = manager.getLast7Days()

        for i in 0..<(days.count - 1) {
            let day1Key = DailyStats.dayKey(for: days[i].date, calendar: cal)
            let day2Key = DailyStats.dayKey(for: days[i + 1].date, calendar: cal)
            XCTAssertLessThan(day1Key, day2Key, "Days should be in chronological order")
        }
    }

    func testGetLast7DaysMissingDaysHaveZeroValues() {
        let date = makeDate(2026, 2, 5)
        let (manager, _, _) = makeManager(now: { date })

        // Only track data for today
        manager.trackTime(interval: 100, isSlouching: false)

        let days = manager.getLast7Days()

        // First 6 days should have zero values (no data recorded for them)
        for i in 0..<6 {
            XCTAssertEqual(days[i].totalSeconds, 0, accuracy: 0.0001,
                           "Day at index \(i) should have zero totalSeconds")
            XCTAssertEqual(days[i].slouchSeconds, 0, accuracy: 0.0001,
                           "Day at index \(i) should have zero slouchSeconds")
            XCTAssertEqual(days[i].slouchCount, 0,
                           "Day at index \(i) should have zero slouchCount")
        }
    }

    func testGetLast7DaysTodayDataAppears() {
        let date = makeDate(2026, 2, 5)
        let cal = calendar
        let (manager, _, _) = makeManager(now: { date })

        manager.trackTime(interval: 42, isSlouching: false)

        let days = manager.getLast7Days()
        let todayKey = DailyStats.dayKey(for: date, calendar: cal)
        let lastDay = days.last!
        let lastDayKey = DailyStats.dayKey(for: lastDay.date, calendar: cal)

        XCTAssertEqual(lastDayKey, todayKey)
        XCTAssertEqual(lastDay.totalSeconds, 42, accuracy: 0.0001)
    }

    // MARK: - DailyStats.postureScore Edge Cases

    func testPostureScoreIs100WhenNoSlouching() {
        let stats = DailyStats(date: Date(), totalSeconds: 100, slouchSeconds: 0, slouchCount: 0)
        XCTAssertEqual(stats.postureScore, 100.0, accuracy: 0.0001)
    }

    func testPostureScoreIs0WhenAllSlouching() {
        let stats = DailyStats(date: Date(), totalSeconds: 100, slouchSeconds: 100, slouchCount: 5)
        XCTAssertEqual(stats.postureScore, 0.0, accuracy: 0.0001)
    }

    func testPostureScoreWithPartialSlouching() {
        let stats = DailyStats(date: Date(), totalSeconds: 100, slouchSeconds: 25, slouchCount: 3)
        // (1.0 - 25/100) * 100 = 75.0
        XCTAssertEqual(stats.postureScore, 75.0, accuracy: 0.0001)
    }

    func testPostureScoreIs0WhenTotalSecondsIsZero() {
        let stats = DailyStats(date: Date(), totalSeconds: 0, slouchSeconds: 0, slouchCount: 0)
        XCTAssertEqual(stats.postureScore, 0.0, accuracy: 0.0001)
    }

    // MARK: - Persistence Tests

    func testDataSurvivesSaveAndReload() throws {
        let date = makeDate(2026, 2, 5)
        let fileURL = makeTempFileURL()
        let queue = DispatchQueue(label: "test.analytics.persist")

        // Create first manager, track data, then force save
        let manager1 = AnalyticsManager(
            fileURL: fileURL,
            calendar: calendar,
            now: { date },
            persistenceQueue: queue
        )
        manager1.trackTime(interval: 60, isSlouching: false)
        manager1.trackTime(interval: 20, isSlouching: true)
        manager1.recordSlouchEvent()
        manager1.recordSlouchEvent()
        manager1.saveHistoryIfNeeded()

        // Wait for async write to complete
        queue.sync {}

        // Create second manager with same file URL - it should load the data
        let manager2 = AnalyticsManager(
            fileURL: fileURL,
            calendar: calendar,
            now: { date },
            persistenceQueue: queue
        )

        XCTAssertEqual(manager2.todayStats.totalSeconds, 80, accuracy: 0.0001)
        XCTAssertEqual(manager2.todayStats.slouchSeconds, 20, accuracy: 0.0001)
        XCTAssertEqual(manager2.todayStats.slouchCount, 2)
    }

    func testSaveHistoryIfNeededDoesNotWriteWhenClean() throws {
        let date = makeDate(2026, 2, 5)
        let fileURL = makeTempFileURL()
        let queue = DispatchQueue(label: "test.analytics.noop")

        let manager = AnalyticsManager(
            fileURL: fileURL,
            calendar: calendar,
            now: { date },
            persistenceQueue: queue
        )

        // Track some data and save it
        manager.trackTime(interval: 10, isSlouching: false)
        manager.saveHistoryIfNeeded()

        // Wait for the persistence queue to finish writing
        queue.sync {}
        // Drain main queue so lastSavedGeneration gets updated
        let expectation = self.expectation(description: "main queue drained")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        // Record file size after first save
        let data1 = try Data(contentsOf: fileURL)

        // Append a marker byte to detect if the file gets rewritten
        let markerData = data1 + Data([0xFF])
        try markerData.write(to: fileURL)

        // Call saveHistoryIfNeeded again without any new tracking calls
        manager.saveHistoryIfNeeded()
        queue.sync {}

        // If saveHistoryIfNeeded was a no-op, the marker byte should still be there
        let data2 = try Data(contentsOf: fileURL)
        XCTAssertEqual(data2.count, markerData.count,
                       "File should not be rewritten when there are no changes")
    }
}
