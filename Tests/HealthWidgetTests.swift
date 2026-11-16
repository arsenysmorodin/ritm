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
