import Foundation

enum WorkoutKind: String, Codable, CaseIterable, Identifiable {
    case strength, mobility, intervals
    var id: Self { self }
    var title: String {
        switch self { case .strength: "Силовая"; case .mobility: "Подвижность"; case .intervals: "Интервальная" }
    }
    var icon: String {
        switch self { case .strength: "dumbbell"; case .mobility: "figure.flexibility"; case .intervals: "bolt" }
    }
}

enum ExerciseUnit: String, Codable, CaseIterable, Identifiable {
    case repetitions, seconds
    var id: Self { self }
    var label: String { self == .repetitions ? "Повторы" : "Секунды" }
    var short: String { self == .repetitions ? "повт." : "сек" }
}

enum Weekday: Int, Codable, CaseIterable, Identifiable {
    case mon = 2, tue, wed, thu, fri, sat, sun = 1
    var id: Self { self }
    var short: String { ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"][Self.allCases.firstIndex(of: self)!] }
}

struct ExercisePlan: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var unit: ExerciseUnit = .repetitions
    var sets = 3
    var target = 10
    var weight: Double = 0
    var rest = 60
}

struct Routine: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var kind: WorkoutKind = .strength
    var weekday: Weekday? = nil
    var exercises: [ExercisePlan] = []
    var setCount: Int { exercises.reduce(0) { $0 + $1.sets } }
    static let quick = Routine(name: "Свободная тренировка")
}

struct Program: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var routines: [Routine]

    static func starter() -> Program {
        Program(name: "Дома, без инвентаря", routines: [
            Routine(name: "Всё тело", weekday: .mon, exercises: [
                ExercisePlan(name: "Приседания", target: 12),
                ExercisePlan(name: "Отжимания", target: 8),
                ExercisePlan(name: "Ягодичный мост", target: 12),
                ExercisePlan(name: "Планка", unit: .seconds, sets: 2, target: 30, rest: 45)
            ]),
            Routine(name: "Ноги и корпус", weekday: .wed, exercises: [
                ExercisePlan(name: "Обратные выпады", target: 10),
                ExercisePlan(name: "Ягодичный мост", target: 12),
                ExercisePlan(name: "Мёртвый жук", target: 10),
                ExercisePlan(name: "Боковая планка", unit: .seconds, sets: 2, target: 20, rest: 45)
            ]),
            Routine(name: "Мягкая подвижность", kind: .mobility, weekday: .sat, exercises: [
                ExercisePlan(name: "Кошка-корова", sets: 2, target: 8, rest: 30),
                ExercisePlan(name: "Повороты грудного отдела", sets: 2, target: 8, rest: 30),
                ExercisePlan(name: "Растяжка сгибателей бедра", unit: .seconds, sets: 2, target: 25, rest: 30)
            ])
        ])
    }
}

struct LoggedSet: Identifiable, Codable, Equatable {
    var id = UUID()
    var value: Int
    var weight: Double
    var complete = false
}

struct LoggedExercise: Identifiable, Codable, Equatable {
    var id = UUID()
    var plan: ExercisePlan
    var sets: [LoggedSet]

    init(_ plan: ExercisePlan) {
        self.plan = plan
        self.sets = (0..<plan.sets).map { _ in LoggedSet(value: plan.target, weight: plan.weight) }
    }
}

struct ActiveWorkout: Identifiable, Codable, Equatable {
    var id = UUID()
    var routineID: UUID?
    var name: String
    var kind: WorkoutKind
    var startedAt: Date
    var exercises: [LoggedExercise]
    var restUntil: Date? = nil
    var notes = ""

    init(routine: Routine?, now: Date) {
        let template = routine ?? .quick
        routineID = routine?.id
        name = template.name
        kind = template.kind
        startedAt = now
        exercises = template.exercises.map(LoggedExercise.init)
    }

    var marked: Int { exercises.reduce(0) { $0 + $1.sets.filter(\.complete).count } }
    var total: Int { exercises.reduce(0) { $0 + $1.sets.count } }
    func secondsLeft(at date: Date) -> Int { max(0, Int(ceil(restUntil?.timeIntervalSince(date) ?? 0))) }
}

struct WorkoutRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var routineID: UUID?
    var name: String
    var kind: WorkoutKind
    var startedAt: Date
    var endedAt: Date
    var exercises: [LoggedExercise]
    var notes: String
    var healthExported = false
    var healthExportRequestedAt: Date?

    var awaitsHealthExport: Bool { !healthExported && healthExportRequestedAt != nil }

    var duration: Int { max(1, Int(endedAt.timeIntervalSince(startedAt))) }
    var sets: Int { exercises.reduce(0) { $0 + $1.sets.count } }

    init(_ draft: ActiveWorkout, endedAt: Date) {
        id = draft.id
        routineID = draft.routineID
        name = draft.name
        kind = draft.kind
        startedAt = draft.startedAt
        self.endedAt = max(endedAt, draft.startedAt.addingTimeInterval(1))
        exercises = draft.exercises.compactMap {
            var exercise = $0
            exercise.sets = exercise.sets.filter(\.complete)
            return exercise.sets.isEmpty ? nil : exercise
        }
        notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct Journal: Codable, Equatable {
    let version: Int
    var programs: [Program]
    var activeProgramID: UUID?
    var activeWorkout: ActiveWorkout?
    var records: [WorkoutRecord]
    var weeklyGoal: Int
    var healthEnabled: Bool

    static func fresh() -> Journal {
        let first = Program.starter()
        return Journal(version: 1, programs: [first], activeProgramID: first.id, activeWorkout: nil,
                       records: [], weeklyGoal: 3, healthEnabled: false)
    }

    var activeProgram: Program? { programs.first { $0.id == activeProgramID } }

    func suggestion(on date: Date, calendar: Calendar = .current) -> Routine? {
        let routines = activeProgram?.routines ?? []
        let today = Weekday(rawValue: calendar.component(.weekday, from: date))
        let completed = Set(records.filter { calendar.isDate($0.startedAt, inSameDayAs: date) }.compactMap(\.routineID))
        let remaining = routines.filter { !completed.contains($0.id) }
        return remaining.first { $0.weekday == today } ?? remaining.first ?? routines.first
    }

    func week(containing date: Date, calendar base: Calendar = .current) -> [TrainingDay] {
        var calendar = base
        calendar.firstWeekday = Weekday.mon.rawValue
        guard let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.startedAt) }
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let weekday = Weekday.allCases[offset]
            return TrainingDay(date: day, weekday: weekday, isToday: calendar.isDate(day, inSameDayAs: date),
                               planned: activeProgram?.routines.contains { $0.weekday == weekday } ?? false,
                               count: grouped[day]?.count ?? 0)
        }
    }
}

struct TrainingDay: Identifiable {
    var id: Date { date }
    let date: Date
    let weekday: Weekday
    let isToday: Bool
    let planned: Bool
    let count: Int
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
