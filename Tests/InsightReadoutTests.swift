import Foundation
import Testing
@testable import RitmCore

struct InsightReadoutTests {
    @Test func reversedLaterResultHasPriorityOverAnAttractiveInitialDifference() {
        let result = HealthComparison(a: Array(repeating: 48, count: 8), b: Array(repeating: 60, count: 16),
                                      interval: -2...20, validationDelta: -3)
        let readout = ComparisonReadout(result: result, kind: .association)
        #expect(readout.hasData)
        #expect(readout.signal == .reversed)
        #expect(readout.headline == "Результат не повторился")
        #expect(result.delta == 12)
    }
    @Test func smallGroupsAndUnvalidatedAssociationsAreNotPresentedAsConfirmedResults() {
        #expect(ComparisonReadout(result: .init(a: [1, 2], b: [4, 5, 6]), kind: .association).signal == .insufficient)
        let sample = HealthComparison(a: [1, 2, 3], b: [4, 5, 6])
        #expect(ComparisonReadout(result: sample, kind: .association).signal == .unvalidated)
        #expect(ComparisonReadout(result: sample, kind: .periods).signal == .difference)
        var uncertain = sample
        uncertain.interval = -1...7
        #expect(ComparisonReadout(result: uncertain, kind: .association).signal == .uncertain)
        uncertain.interval = 1...7; uncertain.validationDelta = 2
        #expect(ComparisonReadout(result: uncertain, kind: .association).signal == .repeated)
        let initialZero = HealthComparison(a: [3, 3, 3], b: [3, 3, 3], validationDelta: 4)
        #expect(ComparisonReadout(result: initialZero, kind: .association).signal == .uncertain)
    }
    @Test func barsShareAZeroOriginForBothPositiveAndNegativeValues() {
        let positive = ComparisonBarGeometry([54.9, 66.5])
        #expect(positive.lower == 0 && positive.upper == 66.5)
        #expect(positive.width(66.5) == 1)
        #expect(positive.width(54.9) > 0.8)
        let signed = ComparisonBarGeometry([-2, 4])
        #expect(abs(signed.zero - 1 / 3.0) < 0.000001)
        #expect(signed.start(-2) == 0)
        #expect(signed.start(4) == signed.zero)
        let zero = ComparisonBarGeometry([0, 0])
        #expect(zero.width(0) == 0 && zero.zero.isFinite)
    }
    @Test func plotDoesNotConnectMissingDaysOrDifferentSources() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        func row(_ offset: Int, _ source: String) -> DailyHealth {
            DailyHealth(date: calendar.date(byAdding: .day, value: offset, to: start)!, values: [.hrv: 50], sources: [.hrv: source])
        }
        let rows = [row(0, "A"), row(1, "A"), row(3, "A"), row(4, "B")]
        let points = InsightPlotPoint.make(rows.reversed(), metric: .hrv, calendar: calendar)
        #expect(points.count == 4)
        #expect(points[0].series == points[1].series)
        #expect(points[1].series != points[2].series)
        #expect(points[2].series != points[3].series)
    }
    @Test func durationAndSmallSignedChangesRetainTheirMeaning() {
        #expect(InsightFormat.value(419.6, metric: .sleepMinutes) == "7 ч 0 мин")
        #expect(InsightFormat.delta(-4, metric: .hrv) == "−4 мс")
        #expect(InsightFormat.delta(0.04, metric: .temperature).contains("0,04"))
    }
}
