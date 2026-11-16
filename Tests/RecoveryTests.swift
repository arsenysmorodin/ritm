import Foundation
import Testing
@testable import RitmCore

struct RecoveryTests {
    private let watch = RecoverySource(id: "watch", name: "Watch")
    private let other = RecoverySource(id: "other", name: "Other")
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func overnightDeduplicatesSourcesAndKeepsAwakeSeparateFromSleep() throws {
        let evening = date(8, hour: 23)
        let midnight = date(9)
        let morning = date(9, hour: 7)
        let samples = [
            span(evening, morning, .unspecified, other),
            span(evening, midnight, .deep, watch),
            span(midnight, morning, .core, watch),
            span(midnight, morning, .core, watch),
            span(date(9, hour: 3), date(9, hour: 3, minute: 20), .awake, watch),
            span(evening.addingTimeInterval(-600), morning.addingTimeInterval(600), .inBed, watch),
            span(date(9, hour: 14), date(9, hour: 15), .unspecified, watch)
        ]
        let nights = SleepAnalysis.mainNights(samples, through: date(9, hour: 16), calendar: utc)
        #expect(nights.count == 1)
        let night = try #require(nights.first)
        #expect(night.day == midnight)
        #expect(night.sourceID == watch.id)
        #expect(night.sleptSeconds == 460 * 60)
        #expect(night.phaseSeconds(.deep) == 3600)
        #expect(night.phaseSeconds(.awake) == 1200)
        #expect(night.phaseSeconds(.rem) == nil)
        #expect(night.inBedSeconds == 30_000.0)
        #expect(night.efficiency == 0.92)
        #expect(night.spans.first?.start == evening)
        #expect(night.spans.last?.end == morning)
    }

    @Test func inBedAloneNeverBecomesSleepAndClockSpreadWrapsMidnight() throws {
        let days = [
            span(date(8, hour: 23, minute: 50), date(9, hour: 7, minute: 30), .unspecified, watch),
            span(date(10, hour: 0, minute: 10), date(10, hour: 7, minute: 50), .unspecified, watch),
            span(date(9, hour: 23), date(10, hour: 8), .inBed, other)
        ]
        let now = date(10, hour: 14)
        let snapshot = RecoverySnapshot.analyze(nights: SleepAnalysis.mainNights(days, through: now, calendar: utc),
                                                samples: [], calendar: utc)
        let schedule = snapshot.schedule(endingAt: now, calendar: utc)
        #expect(schedule.days.count == 7)
        #expect(schedule.nights == 2)
        #expect(schedule.onsetSpread == 20)
        #expect(schedule.wakeSpread == 20)
        let overnight = try #require(schedule.days.first { $0.sleep != nil })
        let start = try #require(overnight.sleep?.start)
        #expect(overnight.offset(of: start, calendar: utc) == -10)
        #expect(snapshot.days.allSatisfy { $0.sleep?.stagedSeconds == 0 && $0.sleep?.inBedSeconds == nil })
        #expect(snapshot.recentNight(at: date(12, hour: 8), calendar: utc) == nil)
    }

    @Test func sleepDurationFollowsElapsedTimeAcrossDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 7)))
        let sleep = span(start, end, .core, watch)
        let night = try #require(SleepAnalysis.mainNights([sleep], through: end, calendar: calendar).first)
        #expect(night.sleptSeconds == 7 * 3600)
        let slot = SleepScheduleDay(date: night.day, sleep: night)
        #expect(slot.offset(of: end, calendar: calendar) - slot.offset(of: start, calendar: calendar) == 8 * 60)
    }

    @Test func comparesNightlyMediansWithPriorComparableDaysOnly() throws {
        let sleep: [SleepSample] = (2...10).flatMap { day in
            [
                span(date(day - 1, hour: 23), date(day, hour: 3), .core, watch),
                span(date(day, hour: 3), date(day, hour: 3, minute: 10), .awake, watch),
                span(date(day, hour: 3, minute: 10), date(day, hour: 7), .rem, watch)
            ]
        }
        let now = date(10, hour: 9)
        let samples = (2...10).flatMap { day in
            let source = day == 2 ? other : watch
            return [
                sample(.hrv, on: date(day, hour: 2), value: day == 10 ? 27 : 42, from: source),
                sample(.hrv, on: date(day, hour: 3, minute: 5), value: 200, from: watch),
                sample(.hrv, on: date(day, hour: 5), value: day == 10 ? 33 : 50, from: source),
                sample(.hrv, on: date(day, hour: 8), value: 99, from: watch),
                sample(.sleepingPulse, on: date(day, hour: 4), value: 51, from: watch)
            ]
        }
        let snapshot = RecoverySnapshot.analyze(nights: SleepAnalysis.mainNights(sleep, through: now, calendar: utc),
                                                samples: samples, calendar: utc)
        let current = try #require(snapshot.recentDay(at: now, calendar: utc))
        #expect(current.readings[.hrv]?.value == 30)
        #expect(current.readings[.hrv]?.count == 2)
        let range = try #require(snapshot.range(for: .hrv, on: current, calendar: utc))
        #expect(range.count == 7)
        #expect(range.median == 46)
        #expect(range.position(for: 30) == .below)
        let insufficient = try #require(snapshot.days.first { $0.date == date(9) })
        #expect(snapshot.range(for: .hrv, on: insufficient, calendar: utc) == nil)
        #expect(snapshot.historyCount(for: .hrv, on: insufficient, calendar: utc) == 6)
        #expect(current.readings[.restingPulse] == nil)
    }

    private func date(_ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func span(_ start: Date, _ end: Date, _ phase: SleepPhase, _ source: RecoverySource) -> SleepSample {
        SleepSample(span: SleepSpan(start: start, end: end, phase: phase), source: source)
    }

    private func sample(_ metric: RecoveryMetric, on date: Date, value: Double, from source: RecoverySource) -> RecoverySample {
        RecoverySample(metric: metric, date: date, value: value, source: source)
    }
}
