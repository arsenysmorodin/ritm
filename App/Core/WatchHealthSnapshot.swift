import Foundation

enum WatchCheckInField: String, Codable, CaseIterable, Identifiable, Sendable {
    case energy, stress, sleepiness, soreness, digestion
    var id: String { rawValue }
    var title: String {
        switch self {
        case .energy: "Энергия"
        case .stress: "Стресс"
        case .sleepiness: "Сонливость"
        case .soreness: "Боль в мышцах"
        case .digestion: "Комфорт ЖКТ"
        }
    }
    var endpoints: String {
        switch self {
        case .energy: "1 — мало сил · 5 — много сил"
        case .digestion: "1 — дискомфорт · 5 — комфортно"
        default: "1 — почти нет · 5 — выражено"
        }
    }
}

struct WatchHealthAction: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case water, checkIn }
    var id = UUID()
    var kind: Kind
    var date = Date.now
    var timezone = TimeZone.current.identifier
    var amount: Int?
    var ratings: [String: Int] = [:]

    func isValid(at now: Date) -> Bool {
        guard date.timeIntervalSince1970 >= 0, date <= now.addingTimeInterval(60), TimeZone(identifier: timezone) != nil else { return false }
        switch kind {
        case .water: return amount.map { (10...5000).contains($0) } == true && ratings.isEmpty
        case .checkIn:
            let keys = Set(WatchCheckInField.allCases.map(\.rawValue))
            return amount == nil && !ratings.isEmpty && ratings.allSatisfy { keys.contains($0.key) && (1...5).contains($0.value) }
        }
    }
}

struct WatchHealthReceipt: Codable, Sendable {
    let id: UUID
    let accepted: Bool
}

struct WatchHealthOutbox: Codable, Equatable {
    private(set) var actions: [WatchHealthAction] = []
    mutating func append(_ action: WatchHealthAction) {
        if !actions.contains(where: { $0.id == action.id }) { actions.append(action) }
    }
    mutating func acknowledge(_ receipt: WatchHealthReceipt) {
        if receipt.accepted { actions.removeAll { $0.id == receipt.id } }
    }
}

struct WatchAppContext: Codable, Equatable, Sendable {
    var version = 2
    var workout: WatchSnapshot?
    var health: WatchHealthSnapshot?
}

enum WatchHealthMetricKind: String, Codable, Identifiable, Sendable {
    case sleep, hrv, pulse, restingPulse, steps, activeEnergy, calories, protein, fiber
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sleep: "Сон"
        case .hrv: "Ночная ВСР"
        case .pulse: "Пульс"
        case .restingPulse: "Пульс в покое"
        case .steps: "Шаги"
        case .activeEnergy: "Движение"
        case .calories: "Питание"
        case .protein: "Белок"
        case .fiber: "Клетчатка"
        }
    }
    var unit: String {
        switch self {
        case .sleep: "мин"
        case .hrv: "мс"
        case .pulse, .restingPulse: "уд/мин"
        case .steps: "шагов"
        case .activeEnergy, .calories: "ккал"
        case .protein, .fiber: "г"
        }
    }
}

struct WatchHealthMetric: Codable, Equatable, Identifiable, Sendable {
    var id: WatchHealthMetricKind { kind }
    let kind: WatchHealthMetricKind
    let value: Double
    let measuredAt: Date
    var rangeLower: Double?
    var rangeUpper: Double?
    var historyDays: Int?
}

/// A compact copy of the phone's data. Each measurement keeps its own timestamp.
struct WatchHealthSnapshot: Codable, Equatable, Sendable {
    var version = 1
    var generatedAt = Date.now
    var day: Date
    var readable = true
    var healthEnabled = false
    var metrics: [WatchHealthMetric] = []
    var waterML: Double = 0
    var waterGoal = 2000
    var waterPortions = [150, 250, 500]
    var checkIn: WatchHealthAction?
    var supplementsTaken = 0
    var supplementsPlanned = 0
    var nextSupplement: String?

    func isToday(at now: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(day, inSameDayAs: now)
    }

    func metric(_ kind: WatchHealthMetricKind) -> WatchHealthMetric? { metrics.first { $0.kind == kind } }
}

/// Stable identity prevents a late snapshot or relaunch from repeating a rest alert.
struct WatchRestSignal: Codable, Hashable, Sendable {
    let workoutID: UUID
    let endsAt: Date
    var key: String { "\(workoutID.uuidString).\(endsAt.timeIntervalSince1970)" }
}
