import Foundation

enum SleepPhase: String, Codable, CaseIterable, Identifiable {
    case awake, rem, core, deep, unspecified, inBed
    var id: Self { self }
    var isSleep: Bool { self != .awake && self != .inBed }

    var title: String {
        switch self {
        case .awake: "Бодрствование"
        case .rem: "Быстрый (REM)"
        case .core: "Основной"
        case .deep: "Глубокий"
        case .unspecified: "Без фазы"
        case .inBed: "В постели"
        }
    }

    fileprivate var priority: Int {
        switch self {
        case .awake: 3
        case .rem, .core, .deep: 2
        case .unspecified: 1
        case .inBed: 0
        }
    }
}

struct RecoverySource: Equatable {
    let id: String
    let name: String
}

struct SleepSpan: Codable, Equatable, Identifiable {
    var id: Date { start }
    let start: Date
    let end: Date
    let phase: SleepPhase

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct SleepSample {
    let span: SleepSpan
    let source: RecoverySource
}

struct SleepNight: Codable, Equatable, Identifiable {
    var id: Date { day }
    let day: Date
    let sourceID: String
    let sourceName: String
    let spans: [SleepSpan]
    let inBedSeconds: TimeInterval?

    var start: Date { spans.first?.start ?? day }
    var end: Date { spans.last?.end ?? day }
    var sleptSeconds: TimeInterval { spans.filter(\.phase.isSleep).reduce(0) { $0 + $1.duration } }
    var stagedSeconds: TimeInterval {
        sleptSeconds - (phaseSeconds(.unspecified) ?? 0)
    }

    var efficiency: Double? {
        inBedSeconds.flatMap { $0 > 0 ? sleptSeconds / $0 : nil }
    }

    func phaseSeconds(_ phase: SleepPhase) -> TimeInterval? {
        let matching = spans.filter { $0.phase == phase }
        return matching.isEmpty ? nil : matching.reduce(0) { $0 + $1.duration }
    }
}

enum RecoveryMetric: String, Codable, CaseIterable, Identifiable {
    case hrv, restingPulse, sleepingPulse, respiration, oxygen, wristTemperature

    var id: Self { self }

    var title: String {
        switch self {
        case .hrv: "Ночная ВСР (SDNN)"
        case .restingPulse: "Пульс в покое"
        case .sleepingPulse: "Пульс во сне"
        case .respiration: "Частота дыхания"
        case .oxygen: "Кислород во сне"
        case .wristTemperature: "Температура запястья"
        }
    }

    var shortTitle: String {
        switch self {
        case .hrv: "Ночная ВСР"
        case .restingPulse: "Пульс в покое"
        default: title
        }
    }

    var unit: String {
        switch self {
        case .hrv: "мс"
        case .restingPulse, .sleepingPulse: "уд/мин"
        case .respiration: "вд/мин"
        case .oxygen: "%"
        case .wristTemperature: "°C"
        }
    }

    var isNightly: Bool { self != .restingPulse }

    func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...(self == .wristTemperature || self == .respiration ? 1 : 0)))
            .locale(Locale(identifier: "ru_RU"))) + (self == .oxygen ? "%" : " " + unit)
    }

    fileprivate func accepts(_ value: Double) -> Bool {
        value.isFinite && (self == .oxygen ? (0...100).contains(value) && value > 0 : value > 0)
    }
}

struct RecoverySample {
    let metric: RecoveryMetric
    let date: Date
    let value: Double
    let source: RecoverySource
}

struct RecoveryReading: Codable, Equatable {
    let date: Date
    let value: Double
    let sourceID: String
    let sourceName: String
    let count: Int
}

struct RecoveryDay: Codable, Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let sleep: SleepNight?
    var readings: [RecoveryMetric: RecoveryReading]
}

struct RecoveryRange: Equatable {
    static let historyDays = 28
    static let minimumDays = 7

    let lower: Double
    let median: Double
    let upper: Double
    let count: Int

    enum Position {
        case below, within, above
        var title: String {
            switch self {
            case .below: "Ниже личного диапазона"
            case .within: "В личном диапазоне"
            case .above: "Выше личного диапазона"
            }
        }
    }

    func position(for value: Double) -> Position {
        if value < lower { return .below }
        if value > upper { return .above }
        return .within
    }

    fileprivate init(sorted: [Double]) {
        lower = Self.quantile(sorted, at: 0.10)
        median = Self.quantile(sorted, at: 0.50)
        upper = Self.quantile(sorted, at: 0.90)
        count = sorted.count
    }

    fileprivate static func quantile(_ sorted: [Double], at fraction: Double) -> Double {
        let rank = Double(sorted.count - 1) * fraction
        let low = Int(rank.rounded(.down))
        let high = Int(rank.rounded(.up))
        return sorted[low] + (sorted[high] - sorted[low]) * (rank - Double(low))
    }
}

struct SleepScheduleDay: Identifiable {
    var id: Date { date }
    let date: Date
    let sleep: SleepNight?

    func offset(of time: Date, calendar: Calendar) -> Int {
        let dayOffset = calendar.dateComponents([.day], from: date, to: calendar.startOfDay(for: time)).day ?? 0
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        return dayOffset * 1440 + (clock.hour ?? 0) * 60 + (clock.minute ?? 0)
    }
}

struct SleepSchedule {
    let days: [SleepScheduleDay]
    let calendar: Calendar

    var nights: Int { days.filter { $0.sleep != nil }.count }
    var onsetSpread: Int? { spread(days.compactMap { day in day.sleep.map { day.offset(of: $0.start, calendar: calendar) } }) }
    var wakeSpread: Int? { spread(days.compactMap { day in day.sleep.map { day.offset(of: $0.end, calendar: calendar) } }) }

    private func spread(_ times: [Int]) -> Int? {
        guard times.count > 1 else { return nil }
        let sorted = times.map { (($0 % 1440) + 1440) % 1440 }.sorted()
        let gaps = zip(sorted, sorted.dropFirst()).map { $1 - $0 }
        let acrossMidnight = sorted[0] + 1440 - sorted[sorted.count - 1]
        return 1440 - max(acrossMidnight, gaps.max() ?? 0)
    }
}

enum RecoveryWidgetKind: String, CaseIterable {
    case recovery = "RitmRecovery"
    case stages = "RitmSleepStages"
    case measurements = "RitmSleepVitals"
    case schedule = "RitmSleepSchedule"
}

struct RecoverySnapshot: Codable, Equatable {
    static let file = "recovery.json"
    static let widgetKinds = RecoveryWidgetKind.allCases.map(\.rawValue)
    static let defaultSleepMinutes = 480
    static let sleepGoalRange = 180...720

    let days: [RecoveryDay]

    func recentDay(at date: Date, calendar: Calendar = .current) -> RecoveryDay? {
        recentDays(2, endingAt: date, calendar: calendar).last
    }

    func recentNight(at date: Date, calendar: Calendar = .current) -> RecoveryDay? {
        recentDays(2, endingAt: date, calendar: calendar).last { $0.sleep != nil }
    }

    func recentDays(_ count: Int, endingAt date: Date, calendar: Calendar = .current) -> [RecoveryDay] {
        guard count > 0, let start = calendar.date(byAdding: .day, value: 1 - count, to: calendar.startOfDay(for: date)) else { return [] }
        let end = calendar.startOfDay(for: date)
        return days.filter { (start...end).contains($0.date) }
    }

    func schedule(endingAt date: Date, calendar: Calendar = .current) -> SleepSchedule {
        let observed = Dictionary(grouping: recentDays(7, endingAt: date, calendar: calendar), by: \.date)
        let today = calendar.startOfDay(for: date)
        let slots = (-6...0).compactMap { offset -> SleepScheduleDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return SleepScheduleDay(date: date, sleep: observed[date]?.first?.sleep)
        }
        return SleepSchedule(days: slots, calendar: calendar)
    }

    func historyCount(for metric: RecoveryMetric, on day: RecoveryDay, calendar: Calendar = .current) -> Int {
        history(for: metric, on: day, calendar: calendar).count
    }

    func range(for metric: RecoveryMetric, on day: RecoveryDay, calendar: Calendar = .current) -> RecoveryRange? {
        let history = history(for: metric, on: day, calendar: calendar)
        guard history.count >= RecoveryRange.minimumDays else { return nil }
        return RecoveryRange(sorted: history.sorted())
    }

    private func history(for metric: RecoveryMetric, on day: RecoveryDay, calendar: Calendar) -> [Double] {
        guard let current = day.readings[metric],
              let start = calendar.date(byAdding: .day, value: -RecoveryRange.historyDays, to: day.date) else { return [] }
        return days.lazy.filter { $0.date >= start && $0.date < day.date }.compactMap {
            guard let reading = $0.readings[metric], reading.sourceID == current.sourceID else { return nil }
            return reading.value
        }
    }

    static func analyze(nights: [SleepNight], samples: [RecoverySample], calendar: Calendar = .current) -> Self {
        let clean = samples.filter { $0.metric.accepts($0.value) }
        let nightly = clean.filter(\.metric.isNightly).sorted { $0.date < $1.date }
        var days = Dictionary(uniqueKeysWithValues: nights.map { ($0.day, RecoveryDay(date: $0.day, sleep: $0, readings: [:])) })
        var cursor = nightly.startIndex
        for night in nights.sorted(by: { $0.start < $1.start }) {
            while cursor < nightly.endIndex && nightly[cursor].date < night.start { cursor += 1 }
            let inWindow = nightly[cursor...].prefix { $0.date <= night.end }
            let asleep = night.spans.filter(\.phase.isSleep)
            var span = asleep.startIndex
            let duringSleep = inWindow.filter { sample in
                if sample.metric == .wristTemperature { return true }
                while span < asleep.endIndex && asleep[span].end <= sample.date { span += 1 }
                return span < asleep.endIndex && asleep[span].start <= sample.date
            }
            for (metric, group) in Dictionary(grouping: duringSleep, by: \.metric) {
                days[night.day]?.readings[metric] = reading(group, preferredSource: night.sourceID)
            }
        }
        let resting = Dictionary(grouping: clean.filter { !$0.metric.isNightly }) { calendar.startOfDay(for: $0.date) }
        for (date, group) in resting {
            guard let latest = group.max(by: { $0.date < $1.date }) else { continue }
            let value = RecoveryReading(date: latest.date, value: latest.value, sourceID: latest.source.id,
                                        sourceName: latest.source.name, count: 1)
            days[date, default: RecoveryDay(date: date, sleep: nil, readings: [:])].readings[.restingPulse] = value
        }
        return Self(days: days.values.sorted { $0.date < $1.date })
    }

    private static func reading(_ samples: [RecoverySample], preferredSource: String) -> RecoveryReading? {
        let bySource = Dictionary(grouping: samples, by: \.source.id)
        let selected = bySource[preferredSource] ?? bySource.keys.sorted().compactMap { bySource[$0] }
            .max { $0.count < $1.count }
        guard let selected, let latest = selected.max(by: { $0.date < $1.date }) else { return nil }
        let median = RecoveryRange.quantile(selected.map(\.value).sorted(), at: 0.5)
        return RecoveryReading(date: latest.date, value: median, sourceID: latest.source.id,
                               sourceName: latest.source.name, count: selected.count)
    }
}

enum SleepAnalysis {
    private static let maximumGap: TimeInterval = 90 * 60

    static func mainNights(_ samples: [SleepSample], through now: Date, calendar: Calendar = .current) -> [SleepNight] {
        let valid = samples.filter { $0.span.duration > 0 && $0.span.duration <= 36 * 3600 && $0.span.end <= now }
        let options = Dictionary(grouping: valid, by: \.source.id).values.flatMap { sourceNights($0, calendar: calendar) }
        // Competing sources can place a wake-up on opposite sides of midnight.
        let selected = Dictionary(grouping: options, by: \.day).values.compactMap(best)
            .sorted { $0.start < $1.start }
        var nights: [SleepNight] = []
        for option in selected {
            if let previous = nights.last, option.start < previous.end {
                nights[nights.count - 1] = best([previous, option]) ?? previous
            } else {
                nights.append(option)
            }
        }
        return nights.sorted { $0.day < $1.day }
    }

    private static func best(_ options: [SleepNight]) -> SleepNight? {
        let longest = options.map(\.sleptSeconds).max() ?? 0
        return options.filter { $0.sleptSeconds >= longest * 0.8 }.sorted {
            if $0.stagedSeconds != $1.stagedSeconds { return $0.stagedSeconds > $1.stagedSeconds }
            if $0.sleptSeconds != $1.sleptSeconds { return $0.sleptSeconds > $1.sleptSeconds }
            return $0.sourceID < $1.sourceID
        }.first
    }

    private static func sourceNights(_ samples: [SleepSample], calendar: Calendar) -> [SleepNight] {
        guard let source = samples.first?.source else { return [] }
        let spans = samples.map(\.span).sorted { $0.start < $1.start }
        let episodes = merged(spans.filter(\.phase.isSleep), gap: maximumGap)
        let inBed = merged(spans.filter { $0.phase == .inBed }, gap: 0)
        return episodes.compactMap { episode in
            let segments = partition(spans, in: episode)
            guard let first = segments.firstIndex(where: \.phase.isSleep),
                  let last = segments.lastIndex(where: \.phase.isSleep) else { return nil }
            let recorded = Array(segments[first...last])
            let start = recorded[0].start
            let end = recorded[recorded.count - 1].end
            let covering = inBed.first { $0.start <= start && $0.end >= end }
            return SleepNight(day: calendar.startOfDay(for: end), sourceID: source.id, sourceName: source.name,
                              spans: recorded, inBedSeconds: covering?.duration)
        }
    }

    private static func merged(_ spans: [SleepSpan], gap: TimeInterval) -> [DateInterval] {
        var result: [DateInterval] = []
        for span in spans {
            if let last = result.last, span.start.timeIntervalSince(last.end) <= gap {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, span.end))
            } else {
                result.append(DateInterval(start: span.start, end: span.end))
            }
        }
        return result
    }

    private static func partition(_ spans: [SleepSpan], in episode: DateInterval) -> [SleepSpan] {
        let candidates = spans.filter { $0.phase != .inBed && $0.start < episode.end && $0.end > episode.start }
        let boundaries = Set(candidates.flatMap { [max(episode.start, $0.start), min(episode.end, $0.end)] }).sorted()
        var result: [SleepSpan] = []
        for (start, end) in zip(boundaries, boundaries.dropFirst()) {
            let phase = candidates.lazy.filter { $0.start <= start && $0.end >= end }
                .max { lhs, rhs in
                    if lhs.phase.priority != rhs.phase.priority { return lhs.phase.priority < rhs.phase.priority }
                    if lhs.start != rhs.start { return lhs.start < rhs.start }
                    return lhs.phase.rawValue < rhs.phase.rawValue
                }?.phase
            guard let phase else { continue }
            if let last = result.last, last.end == start, last.phase == phase {
                result[result.count - 1] = SleepSpan(start: last.start, end: end, phase: phase)
            } else {
                result.append(SleepSpan(start: start, end: end, phase: phase))
            }
        }
        return result
    }
}

enum RecoveryFeeling: Int, CaseIterable, Identifiable, Codable {
    case exhausted = 1, tired, okay, good, fresh
    var id: Self { self }
    var title: String {
        switch self {
        case .exhausted: "Очень устал"
        case .tired: "Устал"
        case .okay: "Нормально"
        case .good: "Хорошо"
        case .fresh: "Бодро"
        }
    }
}

struct RecoveryCheckIn: Codable, Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let feeling: RecoveryFeeling
}
