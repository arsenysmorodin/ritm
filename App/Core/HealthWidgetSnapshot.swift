import Foundation

enum Nutrient: String, CaseIterable, Codable {
    case energy, protein, fat, carbs, fiber, sugar, saturatedFat, sodium

    var title: String {
        switch self {
        case .energy: "Энергия"
        case .protein: "Белки"
        case .fat: "Жиры"
        case .carbs: "Углеводы"
        case .fiber: "Клетчатка"
        case .sugar: "Сахара"
        case .saturatedFat: "Насыщ. жиры"
        case .sodium: "Натрий"
        }
    }

    var unit: String {
        switch self {
        case .energy: "ккал"
        case .sodium: "мг"
        default: "г"
        }
    }
}

struct NutritionGoals: Codable, Equatable {
    static let nutrients: [Nutrient] = [.energy, .protein, .fat, .carbs, .fiber]
    var amounts: [Nutrient: Int] = [:]

    subscript(_ nutrient: Nutrient) -> Int? {
        guard let value = amounts[nutrient], Self.range(for: nutrient).contains(value) else { return nil }
        return value
    }

    static func range(for nutrient: Nutrient) -> ClosedRange<Int> {
        1...(nutrient == .energy ? 20_000 : 2000)
    }
}

struct WidgetTargets: Codable, Equatable {
    static let file = "targets.json"
    let nutrition: NutritionGoals
    let sleepMinutes: Int

    static func load() -> Self {
        WidgetStorage.load(Self.self, file: file) ?? Self(nutrition: NutritionGoals(), sleepMinutes: RecoverySnapshot.defaultSleepMinutes)
    }
}

struct CardiacReading: Codable, Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let value: Double
}

struct CardiacSeries: Codable, Equatable {
    let latest: CardiacReading?
    let today: [CardiacReading]

    init(_ readings: [CardiacReading], from start: Date, through end: Date) {
        let sorted = readings.filter { $0.date <= end && $0.value.isFinite && $0.value > 0 }
            .sorted { $0.date < $1.date }
        latest = sorted.last
        var bins: [Int: CardiacReading] = [:]
        for reading in sorted where reading.date >= start {
            bins[Int(reading.date.timeIntervalSince(start) / 600)] = reading
        }
        today = bins.keys.sorted().compactMap { bins[$0] }
    }

    func recent(at date: Date) -> CardiacReading? {
        guard let latest, latest.date <= date, date.timeIntervalSince(latest.date) < 48 * 3600 else { return nil }
        return latest
    }
}

struct HealthWidgetSnapshot: Codable, Equatable {
    static let heartKind = "RitmHeartWidget"
    static let nutritionKind = "RitmNutritionWidget"
    static let file = "health.json"

    let day: Date
    let pulse: CardiacSeries
    let hrv: CardiacSeries
    let nutrition: [Nutrient: Double]

    func isToday(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: date) == day
    }

    func nutrient(_ kind: Nutrient, at date: Date) -> Double? {
        isToday(date) ? nutrition[kind] : nil
    }

    static func isFatSecret(bundleID: String, sourceName: String) -> Bool {
        bundleID.lowercased().split(separator: ".").contains("fatsecret") ||
            sourceName.lowercased().split(whereSeparator: { !$0.isLetter }).contains("fatsecret")
    }
}

struct WeightPoint: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let kilograms: Double

    static func latestPerDay(_ samples: [Self], calendar: Calendar) -> [Self] {
        var latest: [Date: Self] = [:]
        for sample in samples where sample.kilograms.isFinite && sample.kilograms > 0 {
            let day = calendar.startOfDay(for: sample.date)
            if let previous = latest[day], previous.date > sample.date { continue }
            latest[day] = sample
        }
        return latest.values.sorted { $0.date < $1.date }
    }
}

struct ActivityDay: Codable, Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let steps: Int?
    let activeEnergy: Int?
}

struct ActivityWidgetSnapshot: Codable, Equatable {
    static let file = "activity.json"
    static let summaryKind = "RitmHealthToday"
    static let stepsKind = "RitmSteps"
    static let energyKind = "RitmActiveEnergy"
    static let weightKind = "RitmWeight"
    static let widgetKinds = [summaryKind, stepsKind, energyKind, weightKind]

    let days: [ActivityDay]
    let weights: [WeightPoint]

    func day(at date: Date, calendar: Calendar = .current) -> ActivityDay? {
        days.first { $0.date == calendar.startOfDay(for: date) }
    }

    func week(endingAt date: Date, calendar: Calendar = .current) -> [ActivityDay] {
        let today = calendar.startOfDay(for: date)
        return (-6...0).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return self.day(at: day, calendar: calendar) ?? ActivityDay(date: day, steps: nil, activeEnergy: nil)
        }
    }

    func recentWeights(at date: Date, calendar: Calendar = .current) -> [WeightPoint] {
        let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: date)) ?? date
        return weights.filter { (start...date).contains($0.date) }
    }

    func lastWeight(at date: Date) -> WeightPoint? {
        weights.last { $0.date <= date }
    }

    func forWidgets(at date: Date, calendar: Calendar = .current) -> Self {
        let recent = recentWeights(at: date, calendar: calendar)
        let visible = recent.isEmpty ? lastWeight(at: date).map { [$0] } ?? [] : recent
        return Self(days: days, weights: visible)
    }
}
