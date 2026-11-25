import Foundation

enum HealthEventKind: String, Codable, CaseIterable, Identifiable {
    case water, supplement, caffeine, meal, checkIn, context, measurement, experiment
    var id: String { rawValue }
    var title: String {
        switch self {
        case .water: "Вода"
        case .supplement: "Добавка"
        case .caffeine: "Кофеин"
        case .meal: "Приём пищи"
        case .checkIn: "Самочувствие"
        case .context: "Событие"
        case .measurement: "Измерение"
        case .experiment: "Эксперимент"
        }
    }
    var icon: String {
        switch self {
        case .water: "drop"
        case .supplement: "pills"
        case .caffeine: "cup.and.saucer"
        case .meal: "fork.knife"
        case .checkIn: "face.smiling"
        case .context: "flag"
        case .measurement: "waveform.path.ecg"
        case .experiment: "flask"
        }
    }
}

struct SupplementIngredient: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = ""
    var amount: Double = 0
    var unit = IngredientUnit.mg
    /// Canonical spelling only; unlike units are deliberately never added together.
    var key: String { name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU")) + "|" + unit.rawValue }
}

enum IngredientUnit: String, Codable, CaseIterable, Identifiable {
    case mg = "мг", mcg = "мкг", g = "г", iu = "МЕ", ml = "мл"
    var id: String { rawValue }
}

struct Supplement: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = ""
    var portion = "капсула"
    var ingredients: [SupplementIngredient] = []
    var servings: Double = 1
    /// Minutes from midnight in the current local time zone.
    var times: [Int] = [540]
    var weekdays: [Int] = Array(1...7)
    var startsAt = Calendar.current.startOfDay(for: Date.now)
    var endsAt: Date?
    var archived = false
    var notes = ""

    func isScheduled(on day: Date, calendar: Calendar = .current) -> Bool {
        !archived && calendar.startOfDay(for: day) >= calendar.startOfDay(for: startsAt)
        && (endsAt == nil || calendar.startOfDay(for: day) <= calendar.startOfDay(for: endsAt!))
        && weekdays.contains(calendar.component(.weekday, from: day))
    }

    func slots(on day: Date, calendar: Calendar = .current) -> [Date] {
        guard isScheduled(on: day, calendar: calendar) else { return [] }
        return times.sorted().compactMap { minute in
            calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day)
        }
    }
}

struct HealthEvent: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: HealthEventKind
    var date = Date.now
    var timezone = TimeZone.current.identifier
    var offsetSeconds = TimeZone.current.secondsFromGMT()
    var updatedAt = Date.now
    var title = ""
    var amount: Double?
    var unit = ""
    var note = ""
    var source = "Ритм"
    var externalID: String?
    var linkedID: UUID?
    var scheduledAt: Date?
    var skipped = false
    var ingredients: [SupplementIngredient] = []
    var ratings: [String: Int] = [:]
    /// Removals remain as tombstones until a pending HealthKit deletion has completed.
    var deleted = false
    var needsHealthSync = false

    var isLocal: Bool { externalID == nil }
    var summary: String {
        if kind == .supplement { return skipped ? "Пропущено" : "\(Self.number(amount ?? 1)) порц." }
        if let amount { return "\(kind == .measurement ? amount.formatted(.number.precision(.fractionLength(0...6))) : Self.number(amount)) \(unit)" }
        return note
    }
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "ru_RU")))
    }
    static func water(_ ml: Double, at date: Date = .now) -> Self {
        Self(kind: .water, date: date, offsetSeconds: TimeZone.current.secondsFromGMT(for: date), title: "Вода", amount: ml, unit: "мл", needsHealthSync: true)
    }
}

enum HealthQuantityInput {
    static func parse(_ text: String) -> Double? {
        let compact = text.filter { !$0.isWhitespace }.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(compact), value.isFinite else { return nil }
        return value
    }
    static func editingString(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...8)))
    }
}

struct DailyHealth: Codable, Equatable, Identifiable {
    var date: Date
    var timezone = TimeZone.current.identifier
    var values: [HealthMeasure: Double] = [:]
    var sources: [HealthMeasure: String] = [:]
    var counts: [HealthMeasure: Int] = [:]
    var sleepStart: Date?
    var sleepEnd: Date?
    var id: Date { date }
}

enum HealthMeasure: String, Codable, CaseIterable, Identifiable {
    case sleepMinutes, hrv, restingPulse, sleepingPulse, respiration, oxygen, temperature
    case steps, activeEnergy, daylightMinutes, weight, fiber, protein, calories, water, caffeine, energy, stress
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sleepMinutes: "Длительность сна"
        case .hrv: "Ночная ВСР"
        case .restingPulse: "Пульс в покое"
        case .sleepingPulse: "Ночной пульс"
        case .respiration: "Дыхание во сне"
        case .oxygen: "Кислород во сне"
        case .temperature: "Температура запястья"
        case .steps: "Шаги"
        case .activeEnergy: "Активная энергия"
        case .daylightMinutes: "Дневной свет"
        case .weight: "Вес"
        case .fiber: "Клетчатка"
        case .protein: "Белок"
        case .calories: "Энергия питания"
        case .water: "Вода"
        case .caffeine: "Кофеин"
        case .energy: "Энергия по ощущениям"
        case .stress: "Стресс по ощущениям"
        }
    }
    var unit: String {
        switch self {
        case .sleepMinutes, .daylightMinutes: "мин"
        case .hrv: "мс"
        case .restingPulse, .sleepingPulse: "уд/мин"
        case .respiration: "вд/мин"
        case .oxygen: "%"
        case .temperature: "°C"
        case .steps: "шагов"
        case .activeEnergy, .calories: "ккал"
        case .weight: "кг"
        case .fiber, .protein: "г"
        case .water: "мл"
        case .caffeine: "мг"
        case .energy, .stress: "из 5"
        }
    }
    var isNight: Bool {
        [.sleepMinutes, .hrv, .sleepingPulse, .respiration, .oxygen, .temperature].contains(self)
    }
    static var outcomes: [Self] { [.sleepMinutes, .hrv, .restingPulse, .sleepingPulse, .energy, .stress] }
}

struct HealthOSSettings: Codable, Equatable {
    /// A personal logging goal, not a medical hydration prescription.
    var waterGoal = 2000
    var waterPortions = [150, 250, 500]
    var waterReminderTimes: [Int] = []
    var supplementReminders = false
    var writeIntakeToHealth = false
    var importedThrough: Date?
    var proactiveNotifications: ProactiveNotificationSettings?

    var proactive: ProactiveNotificationSettings {
        get { proactiveNotifications ?? ProactiveNotificationSettings() }
        set { proactiveNotifications = newValue }
    }
}

struct HealthExperiment: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = ""
    var conditionA = "Обычный режим"
    var conditionB = "Изменение привычки"
    var outcome = HealthMeasure.sleepMinutes
    var startsAt = Calendar.current.startOfDay(for: Date.now)
    var blockDays = 7
    var blocks: [Bool] = [false, true, true, false]
    var adaptationDays = 1
    var minimumAdherence = 80
    var rule = ""
    var notes = ""
    var finished = false
    var finishedAt: Date?
    var totalDays: Int { blockDays * blocks.count }
    func assignment(on day: Date, calendar: Calendar = .current) -> (isB: Bool, adaptation: Bool)? {
        guard blockDays > 0, let index = calendar.dateComponents([.day], from: calendar.startOfDay(for: startsAt), to: calendar.startOfDay(for: day)).day,
              index >= 0, index < totalDays else { return nil }
        return (blocks[index / blockDays], index % blockDays < adaptationDays)
    }
    var endsAt: Date { Calendar.current.date(byAdding: .day, value: totalDays, to: startsAt) ?? startsAt }
}

struct HealthOSArchive: Codable, Equatable {
    var version = 1
    var settings = HealthOSSettings()
    var supplements: [Supplement] = []
    var events: [HealthEvent] = []
    var days: [DailyHealth] = []
    var experiments: [HealthExperiment] = []

    func validate() throws {
        guard version == 1, (100...10000).contains(settings.waterGoal), !settings.waterPortions.isEmpty,
              settings.waterPortions.allSatisfy({ (10...5000).contains($0) }),
              settings.waterReminderTimes.allSatisfy({ (0..<1440).contains($0) }),
              settings.proactive.isValid,
              supplements.allSatisfy({ !$0.times.isEmpty && $0.times.allSatisfy({ (0..<1440).contains($0) }) && $0.servings > 0 && $0.servings.isFinite }),
              events.allSatisfy({ $0.amount.map({ $0.isFinite && $0 >= 0 }) ?? true }),
              experiments.allSatisfy({ (2...28).contains($0.blockDays) && (0..<$0.blockDays).contains($0.adaptationDays) && $0.blocks.count == 4 }),
              Set(events.map(\.id)).count == events.count,
              Set(supplements.map(\.id)).count == supplements.count,
              Set(experiments.map(\.id)).count == experiments.count else { throw CocoaError(.fileReadCorruptFile) }
    }
}

enum HealthOSLogic {
    static func events(_ all: [HealthEvent], on day: Date, kind: HealthEventKind? = nil, calendar: Calendar = .current) -> [HealthEvent] {
        all.filter { !$0.deleted && calendar.isDate($0.date, inSameDayAs: day) && (kind == nil || $0.kind == kind) }
            .sorted { $0.date > $1.date }
    }

    static func total(_ kind: HealthEventKind, events all: [HealthEvent], day: Date = .now, calendar: Calendar = .current) -> Double {
        events(all, on: day, kind: kind, calendar: calendar).filter { !$0.skipped }.reduce(0) { $0 + ($1.amount ?? 0) }
    }

    static func ingredientTotals(_ events: [HealthEvent], on day: Date, calendar: Calendar = .current) -> [SupplementIngredient] {
        var totals: [String: SupplementIngredient] = [:]
        for event in Self.events(events, on: day, kind: .supplement, calendar: calendar) where !event.skipped {
            for ingredient in event.ingredients {
                var total = totals[ingredient.key] ?? ingredient
                if totals[ingredient.key] == nil { total.amount = 0 }
                total.amount += ingredient.amount * (event.amount ?? 1)
                totals[ingredient.key] = total
            }
        }
        return totals.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func completedSlot(_ slot: Date, supplement: UUID, events: [HealthEvent]) -> Bool {
        events.contains { !$0.deleted && $0.kind == .supplement && $0.linkedID == supplement && $0.scheduledAt == slot }
    }

    static func dailyValues(_ days: [DailyHealth], events: [HealthEvent], calendar: Calendar = .current) -> [DailyHealth] {
        var merged = Dictionary(grouping: days) { calendar.startOfDay(for: $0.date) }.mapValues { $0.last! }
        let groups = Dictionary(grouping: events.filter { !$0.deleted && !$0.skipped }) { calendar.startOfDay(for: $0.date) }
        for (day, logs) in groups {
            var row = merged[day] ?? DailyHealth(date: day)
            for (kind, metric) in [(HealthEventKind.water, HealthMeasure.water), (.caffeine, .caffeine)] {
                let data = logs.filter { $0.kind == kind && $0.amount != nil }
                if !data.isEmpty {
                    row.values[metric] = data.reduce(0) { $0 + ($1.amount ?? 0) }
                    row.sources[metric] = Array(Set(data.map(\.source))).sorted().joined(separator: ", ")
                    row.counts[metric] = data.count
                }
            }
            if let check = logs.filter({ $0.kind == .checkIn }).max(by: { $0.date < $1.date }) {
                for metric in [HealthMeasure.energy, .stress] {
                    if let value = check.ratings[metric.rawValue] {
                        row.values[metric] = Double(value); row.sources[metric] = "Самооценка"; row.counts[metric] = 1
                    }
                }
            }
            merged[day] = row
        }
        return merged.values.sorted { $0.date < $1.date }
    }
}
