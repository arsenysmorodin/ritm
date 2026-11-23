import Foundation

enum HealthExposure: String, CaseIterable, Identifiable {
    case lateCaffeine, lateMeal, eveningTraining, fiber, daylight, stress, waterGoal, supplement, earlyBedtime
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lateCaffeine: "Кофеин за 8 часов до сна"
        case .lateMeal: "Еда менее чем за 3 часа до сна"
        case .eveningTraining: "Тренировка после 19:00"
        case .fiber: "Клетчатка от 25 г"
        case .daylight: "Дневной свет от 30 минут"
        case .stress: "Стресс от 4 из 5"
        case .waterGoal: "Вода от личной цели"
        case .supplement: "Приём выбранной добавки"
        case .earlyBedtime: "Начало сна до полуночи"
        }
    }
}

struct HealthObservation {
    let date: Date
    let value: Double
    let exposed: Bool
    let source: String
    var context = false
    var steps: Double?
    var caffeine: Double?
}

struct HealthComparison {
    let a: [Double]
    let b: [Double]
    var source = ""
    var excludedSources = 0
    var interval: ClosedRange<Double>?
    var validationDelta: Double?
    var contextDays = 0
    var stepsDifference: Double?
    var meanA: Double? { Self.mean(a) }
    var meanB: Double? { Self.mean(b) }
    var delta: Double? {
        guard let a = meanA, let b = meanB else { return nil }; return b - a
    }
    static func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
}

struct ExperimentReport {
    let comparison: HealthComparison
    let expectedDays: Int
    let recordedAdherence: Int
    let adheredDays: Int
    let missingOutcomes: Int
    let adaptationDays: Int
    let blocks: [(isB: Bool, mean: Double?, count: Int)]
    var adherence: Double? { expectedDays == 0 ? nil : Double(adheredDays) / Double(expectedDays) * 100 }
}

enum HealthAnalytics {
    /// The same measurement source is required on both sides of a comparison.
    static func comparable(_ rows: [HealthObservation]) -> (rows: [HealthObservation], source: String, excluded: Int) {
        let groups = Dictionary(grouping: rows.filter { $0.value.isFinite }) { $0.source }
        let best = groups.keys.sorted().max { a, b in
            let countA = groups[a]?.count ?? 0, countB = groups[b]?.count ?? 0
            return countA == countB ? a < b : countA < countB
        }
        let data = best.flatMap { groups[$0] } ?? []
        return (data.sorted { $0.date < $1.date }, best ?? "", rows.count - data.count)
    }

    static func comparePeriods(metric: HealthMeasure, days: [DailyHealth], length: Int, now: Date = .now, calendar: Calendar = .current) -> HealthComparison {
        let end = calendar.startOfDay(for: now) // today is incomplete
        let middle = calendar.date(byAdding: .day, value: -length, to: end) ?? end
        let start = calendar.date(byAdding: .day, value: -2 * length, to: end) ?? end
        let rows = days.filter { $0.date >= start && $0.date < end }.compactMap { day -> HealthObservation? in
            guard let value = day.values[metric] else { return nil }
            return .init(date: day.date, value: value, exposed: day.date >= middle, source: day.sources[metric] ?? "Неизвестный источник")
        }
        let selected = comparable(rows)
        return comparison(selected.rows, source: selected.source, excluded: selected.excluded, calendar: calendar)
    }

    static func observations(exposure: HealthExposure, outcome: HealthMeasure, days: [DailyHealth], events: [HealthEvent], workouts: [WorkoutRecord], waterGoal: Int = 2000, supplementID: UUID? = nil, calendar: Calendar = .current) -> [HealthObservation] {
        let indexed = Dictionary(grouping: days) { calendar.startOfDay(for: $0.date) }.mapValues { $0.last! }
        let logs = Dictionary(grouping: events.filter { !$0.deleted }) { calendar.startOfDay(for: $0.date) }
        return days.compactMap { outcomeDay in
            guard let value = outcomeDay.values[outcome], value.isFinite else { return nil }
            let preceding = calendar.date(byAdding: .day, value: outcome.isNight || outcome == .restingPulse ? -1 : 0, to: outcomeDay.date) ?? outcomeDay.date
            let key = calendar.startOfDay(for: preceding)
            let dayEvents = logs[key] ?? []
            let daily = indexed[key]
            let exposed: Bool
            switch exposure {
            case .lateCaffeine:
                guard let sleepStart = outcomeDay.sleepStart else { return nil }
                let caffeine = events.filter { !$0.deleted && $0.kind == .caffeine && !$0.skipped && $0.date <= sleepStart && sleepStart.timeIntervalSince($0.date) <= 24 * 3600 }
                guard !caffeine.isEmpty else { return nil }
                exposed = caffeine.contains { ($0.amount ?? 0) > 0 && sleepStart.timeIntervalSince($0.date) <= 8 * 3600 }
            case .lateMeal:
                guard let sleepStart = outcomeDay.sleepStart,
                      let meal = events.filter({ !$0.deleted && $0.kind == .meal && $0.date <= sleepStart && sleepStart.timeIntervalSince($0.date) <= 24 * 3600 }).max(by: { $0.date < $1.date }) else { return nil }
                exposed = sleepStart.timeIntervalSince(meal.date) < 3 * 3600
            case .eveningTraining:
                let sessions = workouts.filter { calendar.isDate($0.startedAt, inSameDayAs: preceding) }
                guard !sessions.isEmpty else { return nil } // compares early vs late training, not unlogged rest days
                exposed = sessions.contains { calendar.component(.hour, from: $0.startedAt) >= 19 }
            case .fiber:
                guard let fiber = daily?.values[.fiber] else { return nil }; exposed = fiber >= 25
            case .daylight:
                guard let light = daily?.values[.daylightMinutes] else { return nil }; exposed = light >= 30
            case .stress:
                guard let stress = daily?.values[.stress] else { return nil }; exposed = stress >= 4
            case .waterGoal:
                guard let water = daily?.values[.water] else { return nil }; exposed = water >= Double(waterGoal)
            case .supplement:
                guard let supplementID else { return nil }
                let intake = dayEvents.filter { $0.kind == .supplement && $0.linkedID == supplementID }
                guard !intake.isEmpty else { return nil }; exposed = intake.contains { !$0.skipped }
            case .earlyBedtime:
                guard let sleepStart = outcomeDay.sleepStart else { return nil }
                let hour = calendar.component(.hour, from: sleepStart)
                exposed = hour >= 18 // Bedtimes after midnight belong to the next calendar day.
            }
            return HealthObservation(date: outcomeDay.date, value: value, exposed: exposed,
                source: outcomeDay.sources[outcome] ?? "Неизвестный источник",
                context: dayEvents.contains { $0.kind == .context }, steps: daily?.values[.steps], caffeine: daily?.values[.caffeine])
        }.sorted { $0.date < $1.date }
    }

    static func pattern(exposure: HealthExposure, outcome: HealthMeasure, days: [DailyHealth], events: [HealthEvent], workouts: [WorkoutRecord], waterGoal: Int = 2000, supplementID: UUID? = nil, now: Date = .now, calendar: Calendar = .current) -> HealthComparison {
        let today = calendar.startOfDay(for: now)
        let complete = days.filter { $0.date < today || ((outcome.isNight || outcome == .restingPulse) && $0.date == today) }
        let rows = observations(exposure: exposure, outcome: outcome, days: complete, events: events, workouts: workouts, waterGoal: waterGoal, supplementID: supplementID, calendar: calendar)
        let selected = comparable(rows)
        // Discovery and later chronological holdout are displayed separately; no p-value fishing.
        let split = Int(Double(selected.rows.count) * 0.7)
        let discovery = Array(selected.rows.prefix(split)), validation = Array(selected.rows.dropFirst(split))
        var result = comparison(discovery, source: selected.source, excluded: selected.excluded, calendar: calendar)
        let validationA = validation.filter { !$0.exposed }.map(\.value), validationB = validation.filter(\.exposed).map(\.value)
        if validationA.count >= 4 && validationB.count >= 4 {
            result.validationDelta = HealthComparison.mean(validationB)! - HealthComparison.mean(validationA)!
        }
        return result
    }

    static func report(_ experiment: HealthExperiment, days: [DailyHealth], events: [HealthEvent], now: Date = .now, calendar: Calendar = .current) -> ExperimentReport {
        let today = calendar.startOfDay(for: now)
        let lastDay = min(today, calendar.startOfDay(for: experiment.finishedAt ?? experiment.endsAt))
        var expected = 0, adherence = 0, recorded = 0, missing = 0, adaptation = 0
        var rows: [HealthObservation] = []
        var blockRows = Array(repeating: [HealthObservation](), count: experiment.blocks.count)
        for index in 0..<experiment.totalDays {
            guard let day = calendar.date(byAdding: .day, value: index, to: experiment.startsAt), day < lastDay,
                  let assignment = experiment.assignment(on: day, calendar: calendar) else { continue }
            if assignment.adaptation { adaptation += 1; continue }
            expected += 1
            let check = events.filter { !$0.deleted && $0.kind == .experiment && $0.linkedID == experiment.id && calendar.isDate($0.date, inSameDayAs: day) }.max { $0.updatedAt < $1.updatedAt }
            if let check { recorded += 1; adherence += check.ratings["adhered"] == 1 ? 1 : 0 }
            let outcomeDate = calendar.date(byAdding: .day, value: experiment.outcome.isNight || experiment.outcome == .restingPulse ? 1 : 0, to: day) ?? day
            guard let data = days.first(where: { calendar.isDate($0.date, inSameDayAs: outcomeDate) }), let value = data.values[experiment.outcome] else { missing += 1; continue }
            // Intention-to-treat: assignment defines the group, never a favourable observed result.
            let row = HealthObservation(date: day, value: value, exposed: assignment.isB, source: data.sources[experiment.outcome] ?? "Неизвестный источник")
            rows.append(row); blockRows[index / experiment.blockDays].append(row)
        }
        let selected = comparable(rows)
        var result = comparison(selected.rows, source: selected.source, excluded: selected.excluded, calendar: calendar)
        result.interval = nil // Four intervention blocks cannot support a reliable interval for a treatment effect.
        let blocks = blockRows.enumerated().map { index, values in
            let comparableValues = values.filter { $0.source == selected.source }.map(\.value)
            return (experiment.blocks[index], HealthComparison.mean(comparableValues), comparableValues.count)
        }
        return .init(comparison: result, expectedDays: expected, recordedAdherence: recorded, adheredDays: adherence,
                     missingOutcomes: missing, adaptationDays: adaptation, blocks: blocks)
    }

    private static func comparison(_ rows: [HealthObservation], source: String, excluded: Int, calendar: Calendar) -> HealthComparison {
        let a = rows.filter { !$0.exposed }, b = rows.filter(\.exposed)
        var result = HealthComparison(a: a.map(\.value), b: b.map(\.value), source: source, excludedSources: excluded)
        result.contextDays = rows.filter(\.context).count
        if let stepsA = HealthComparison.mean(a.compactMap(\.steps)), let stepsB = HealthComparison.mean(b.compactMap(\.steps)) { result.stepsDifference = stepsB - stepsA }
        // Resample calendar weeks, rather than treating adjacent daily samples as independent.
        let blocks = Dictionary(grouping: rows) { calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date }.sorted { $0.key < $1.key }.map(\.value)
        if a.count >= 14, b.count >= 14, blocks.count >= 8 {
            var random = DeterministicRandom(seed: 0x5249544D)
            var deltas: [Double] = []
            for _ in 0..<800 {
                let sample = (0..<blocks.count).flatMap { _ in blocks[Int(random.next() % UInt64(blocks.count))] }
                let sa = sample.filter { !$0.exposed }.map(\.value), sb = sample.filter(\.exposed).map(\.value)
                if let ma = HealthComparison.mean(sa), let mb = HealthComparison.mean(sb) { deltas.append(mb - ma) }
            }
            deltas.sort()
            if deltas.count >= 760 { result.interval = deltas[Int(Double(deltas.count) * 0.025)]...deltas[Int(Double(deltas.count) * 0.975)] }
        }
        return result
    }
    private struct DeterministicRandom {
        var seed: UInt64
        mutating func next() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed >> 16 }
    }
}
