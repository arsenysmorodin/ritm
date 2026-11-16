import Charts
import SwiftUI

enum SleepText {
    private static let russian = Locale(identifier: "ru_RU")

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        return duration(minutes: minutes)
    }

    static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder) мин" }
        return remainder == 0 ? "\(hours) ч" : "\(hours) ч \(remainder) мин"
    }

    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(russian))
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(russian))
    }

    static func period(_ sleep: SleepNight) -> String {
        clock(sleep.start) + " — " + clock(sleep.end)
    }
}

private extension SleepPhase {
    var lane: Double {
        switch self {
        case .awake: 4
        case .rem: 3
        case .core: 2
        case .deep: 1
        case .unspecified, .inBed: 0
        }
    }

    var short: String {
        switch self {
        case .awake: "Бодр."
        case .rem: "REM"
        case .core: "Осн."
        case .deep: "Глуб."
        case .unspecified: "Без фазы"
        case .inBed: "В постели"
        }
    }

    var emphasis: Double {
        switch self {
        case .awake: 0.50
        case .rem: 0.86
        case .core: 0.67
        case .deep: 1
        case .unspecified, .inBed: 0.5
        }
    }
}

struct SleepPhaseChart: View {
    let night: SleepNight
    let accent: Color
    let secondary: Color

    var body: some View {
        let rows = SleepPhase.allCases.filter {
            $0 != .inBed && ($0 != .unspecified || night.phaseSeconds(.unspecified) != nil)
        }
        Chart(night.spans) { span in
            RectangleMark(xStart: .value("Начало", span.start), xEnd: .value("Конец", span.end),
                          yStart: .value("Фаза", span.phase.lane - 0.28), yEnd: .value("Фаза", span.phase.lane + 0.28))
                .foregroundStyle(accent.opacity(span.phase.emphasis))
                .cornerRadius(2)
                .accessibilityLabel(span.phase.title)
                .accessibilityValue(SleepText.clock(span.start) + ", " + SleepText.duration(span.duration))
        }
        .chartXScale(domain: night.start...night.end)
        .chartYScale(domain: (rows.contains(.unspecified) ? -0.5 : 0.5)...4.5)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel(SleepText.clock(date)).font(.caption2).foregroundStyle(secondary)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: rows.map(\.lane)) { _ in
                AxisGridLine().foregroundStyle(secondary.opacity(0.2))
            }
            AxisMarks(position: .leading, values: rows.map(\.lane)) { value in
                if let lane = value.as(Double.self), let row = rows.first(where: { $0.lane == lane }) {
                    AxisValueLabel {
                        Text(row.short).font(.caption2).foregroundStyle(secondary)
                    }
                }
            }
        }
        .accessibilityLabel("Фазы сна по времени")
    }
}

struct SleepScheduleChart: View {
    let schedule: SleepSchedule
    let accent: Color
    let secondary: Color
    var compact = false

    var body: some View {
        let points = schedule.days.map { Point(day: $0, calendar: schedule.calendar) }
        let earliest = points.compactMap(\.start).min() ?? -120
        let latest = points.compactMap(\.end).max() ?? 480
        let lower = Int(floor(Double(earliest) / 180)) * 180
        let upper = max(lower + 180, Int(ceil(Double(latest) / 180)) * 180)
        let ticks = Array(stride(from: lower, through: upper, by: upper - lower > 900 ? 360 : 180))
        Chart(points) { point in
            if let start = point.start, let end = point.end, let night = point.day.sleep {
                BarMark(x: .value("День", point.weekday), yStart: .value("Засыпание", start), yEnd: .value("Подъём", end),
                        width: .fixed(compact ? 8 : 14))
                    .foregroundStyle(accent)
                    .cornerRadius(3)
                    .accessibilityLabel(SleepText.shortDate(point.day.date))
                    .accessibilityValue(SleepText.period(night) + ", " + SleepText.duration(night.sleptSeconds))
            } else {
                PointMark(x: .value("День", point.weekday), y: .value("Нет записи", lower + 18))
                    .symbolSize(14).foregroundStyle(secondary.opacity(0.5))
                    .accessibilityLabel(SleepText.shortDate(point.day.date))
                    .accessibilityValue("Нет записи сна")
            }
        }
        .chartXScale(domain: points.map(\.weekday))
        .chartYScale(domain: lower...upper)
        .chartXAxis {
            AxisMarks(values: points.map(\.weekday)) { _ in
                AxisValueLabel().font(.caption2).foregroundStyle(secondary)
            }
        }
        .chartYAxis {
            if !compact {
                AxisMarks(position: .leading, values: ticks) { _ in
                    AxisGridLine().foregroundStyle(secondary.opacity(0.2))
                }
                AxisMarks(position: .leading, values: ticks) { value in
                    if let time = value.as(Int.self) {
                        AxisValueLabel {
                            Text(Self.clockLabel(time)).font(.caption2).foregroundStyle(secondary)
                        }
                    }
                }
            }
        }
        .accessibilityLabel("Время засыпания и подъёма за семь дней")
    }

    private static let weekdays = ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]

    private static func clockLabel(_ minutes: Int) -> String {
        let clock = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", clock / 60, clock % 60)
    }

    private struct Point: Identifiable {
        var id: Date { day.date }
        let weekday: String
        let day: SleepScheduleDay
        let start: Int?
        let end: Int?

        init(day: SleepScheduleDay, calendar: Calendar) {
            self.day = day
            weekday = SleepScheduleChart.weekdays[calendar.component(.weekday, from: day.date) - 1]
            start = day.sleep.map { day.offset(of: $0.start, calendar: calendar) }
            end = day.sleep.map { day.offset(of: $0.end, calendar: calendar) }
        }
    }
}
