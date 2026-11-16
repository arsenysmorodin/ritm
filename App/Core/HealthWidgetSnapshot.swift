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
