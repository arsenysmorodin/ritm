import Foundation

// Presentation only. HealthAnalytics remains the sole source of comparisons.
enum ComparisonKind { case periods, association, experiment }

struct ComparisonReadout {
    enum Signal: Equatable { case insufficient, unchanged, difference, uncertain, unvalidated, repeated, reversed }
    let result: HealthComparison
    var kind: ComparisonKind = .periods
    var hasData: Bool { result.a.count >= 3 && result.b.count >= 3 && result.delta?.isFinite == true }
    var signal: Signal {
        guard hasData, let delta = result.delta else { return .insufficient }
        if kind == .association, let validation = result.validationDelta, delta * validation < 0 { return .reversed }
        if abs(delta) < 0.000001 {
            return kind == .association ? (result.validationDelta == nil ? .unvalidated : .uncertain) : .unchanged
        }
        if kind == .association {
            if result.interval?.contains(0) == true || result.validationDelta == 0 { return .uncertain }
            return result.validationDelta == nil ? .unvalidated : .repeated
        }
        return .difference
    }
    var headline: String {
        switch signal {
        case .insufficient: "Нужно больше данных"
        case .unchanged: "Без изменений"
        case .difference: kind == .experiment ? "Разница между A и B" : "Изменение среднего"
        case .uncertain: "Разница неоднозначна"
        case .unvalidated: "Нужны новые наблюдения"
        case .repeated: "Направление разницы повторилось"
        case .reversed: "Результат не повторился"
        }
    }
}

enum InsightFormat {
    static func value(_ value: Double, metric: HealthMeasure) -> String {
        if metric == .sleepMinutes {
            let minutes = Int(value.rounded())
            return "\(minutes / 60) ч \(abs(minutes % 60)) мин"
        }
        return "\(number(value, precise: metric == .temperature)) \(metric.unit)"
    }
    static func delta(_ value: Double, metric: HealthMeasure) -> String {
        let sign = value > 0 ? "+" : value < 0 ? "−" : ""
        return sign + number(abs(value), precise: abs(value) < 0.1 || metric == .temperature) + " " + metric.unit
    }
    static func number(_ value: Double, precise: Bool = false) -> String {
        value.formatted(.number.precision(.fractionLength(0...(precise ? 2 : 1))).locale(Locale(identifier: "ru_RU")))
    }
}

/// Both comparison bars share a zero origin, including signed measurements.
struct ComparisonBarGeometry {
    let lower: Double
    let upper: Double
    init(_ values: [Double]) {
        let finite = values.filter(\.isFinite)
        lower = min(0, finite.min() ?? 0)
        upper = max(0, finite.max() ?? 0)
    }
    var span: Double { max(upper - lower, 0.000001) }
    var zero: Double { -lower / span }
    func start(_ value: Double) -> Double { (min(0, value) - lower) / span }
    func width(_ value: Double) -> Double { abs(value) / span }
}

struct InsightPlotPoint: Identifiable {
    let date: Date
    let value: Double
    let series: String
    var id: Date { date }

    static func make(_ days: [DailyHealth], metric: HealthMeasure, calendar: Calendar = .current) -> [Self] {
        var result: [Self] = [], segment = 0
        var previous: DailyHealth?
        for day in days.sorted(by: { $0.date < $1.date }) {
            guard let value = day.values[metric], value.isFinite else { continue }
            if let previous {
                let gap = calendar.dateComponents([.day], from: previous.date, to: day.date).day ?? 2
                if gap != 1 || previous.sources[metric] != day.sources[metric] { segment += 1 }
            }
            result.append(Self(date: day.date, value: value, series: "\(segment)"))
            previous = day
        }
        return result
    }
}
