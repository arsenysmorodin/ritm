import Foundation
import Testing
@testable import RitmCore

struct HealthWidgetTests {
    @Test func nutritionRolloverKeepsMissingFiberDistinctFromRecordedZero() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: .now)
        let midnightTomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
        let emptySeries = CardiacSeries([], from: day, through: day)
        let totals = HealthWidgetSnapshot(day: day, pulse: emptySeries, hrv: emptySeries,
                                         nutrition: [.energy: 1780, .fiber: 0])
        #expect(totals.nutrient(.fiber, at: day) == 0)
        #expect(totals.nutrient(.protein, at: day) == nil)
        #expect(totals.nutrient(.energy, at: midnightTomorrow) == nil)
        #expect(HealthWidgetSnapshot.isFatSecret(bundleID: "com.fatsecret.caloriecounter", sourceName: "Calorie Counter"))
        #expect(!HealthWidgetSnapshot.isFatSecret(bundleID: "com.apple.Health", sourceName: "Health"))
    }

    @Test func latestHeartMeasurementCanPrecedeTodayButDoesNotAppearInTodaysChart() {
        let day = Date(timeIntervalSinceReferenceDate: 100_000)
        let latest = CardiacReading(date: day.addingTimeInterval(-60), value: 48)
        let sparse = CardiacSeries([latest], from: day, through: day)
        #expect(sparse.recent(at: day) == latest)
        #expect(sparse.today.isEmpty)
        #expect(sparse.recent(at: day.addingTimeInterval(48 * 3600)) == nil)
        let samples = [latest, CardiacReading(date: day.addingTimeInterval(40), value: 62),
                       CardiacReading(date: day.addingTimeInterval(310), value: 67)]
        let today = CardiacSeries(samples, from: day, through: day.addingTimeInterval(600))
        #expect(today.today == [samples[2]])
        #expect(today.latest == samples[2])
    }
}

@Test func activityWidgetKeepsMissingDaysDistinctFromZeroAndRollsOverAtMidnight() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/Moscow"))
    let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 16)))
    let next = try #require(calendar.date(byAdding: .day, value: 1, to: day))
    let previous = try #require(calendar.date(byAdding: .day, value: -1, to: day))
    let snapshot = ActivityWidgetSnapshot(days: [
        ActivityDay(date: previous, steps: nil, activeEnergy: 120),
        ActivityDay(date: day, steps: 0, activeEnergy: nil)
    ], weights: [])
    #expect(snapshot.day(at: day.addingTimeInterval(3600), calendar: calendar)?.steps == 0)
    #expect(snapshot.day(at: next, calendar: calendar) == nil)
    let week = snapshot.week(endingAt: next, calendar: calendar)
    #expect(week.count == 7)
    #expect(week.last?.steps == nil)
    #expect(week.last?.date == next)
    #expect(week.dropLast().last?.steps == 0)
    #expect(week.dropLast(2).last?.activeEnergy == 120)
}

@Test func weightWidgetPreservesLatestMeasurementOutsideTheTrendWindow() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 18)))
    let cutoff = calendar.startOfDay(for: now)
    let past = try #require(calendar.date(byAdding: .day, value: -30, to: cutoff))
    let firstInWindow = try #require(calendar.date(byAdding: .day, value: -29, to: cutoff))
    let old = WeightPoint(id: UUID(), date: past, kilograms: 74)
    let recent = WeightPoint(id: UUID(), date: firstInWindow, kilograms: 75)
    let future = WeightPoint(id: UUID(), date: now.addingTimeInterval(60), kilograms: 76)
    let snapshot = ActivityWidgetSnapshot(days: [], weights: [old, recent, future])
    #expect(snapshot.lastWeight(at: now) == recent)
    #expect(snapshot.recentWeights(at: now, calendar: calendar) == [recent])
    #expect(snapshot.forWidgets(at: now, calendar: calendar).weights == [recent])

    let oldOnly = ActivityWidgetSnapshot(days: [], weights: [old])
    #expect(oldOnly.lastWeight(at: now) == old)
    #expect(oldOnly.recentWeights(at: now, calendar: calendar).isEmpty)
    #expect(oldOnly.forWidgets(at: now, calendar: calendar).weights == [old])
}
