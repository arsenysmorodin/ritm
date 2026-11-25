import Foundation

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

enum Muscle: String, Codable, CaseIterable, Identifiable {
    case chest, shoulders, biceps, triceps, forearms, abs, obliques
    case upperBack, lats, lowerBack, glutes, quads, hamstrings, calves, adductors, hipFlexors

    var id: Self { self }
    var title: String {
        switch self {
        case .chest: "Грудные"
        case .shoulders: "Плечи"
        case .biceps: "Бицепсы"
        case .triceps: "Трицепсы"
        case .forearms: "Предплечья"
        case .abs: "Пресс"
        case .obliques: "Косые мышцы живота"
        case .upperBack: "Верх спины"
        case .lats: "Широчайшие"
        case .lowerBack: "Поясница"
        case .glutes: "Ягодичные"
        case .quads: "Передняя поверхность бедра"
        case .hamstrings: "Задняя поверхность бедра"
        case .calves: "Икры"
        case .adductors: "Внутренняя поверхность бедра"
        case .hipFlexors: "Сгибатели бедра"
        }
    }
}

struct MuscleSelection: Codable, Equatable {
    var primary: [Muscle] = []
    var secondary: [Muscle] = []
    var isEmpty: Bool { primary.isEmpty && secondary.isEmpty }

    static func combined(_ selections: [Self]) -> Self {
        let primary = Set(selections.flatMap(\.primary))
        let secondary = Set(selections.flatMap(\.secondary)).subtracting(primary)
        return Self(primary: Muscle.allCases.filter(primary.contains), secondary: Muscle.allCases.filter(secondary.contains))
    }
}

struct DropStagePlan: Codable, Equatable {
    var repetitions: Int
    var weight: Double
}

struct ExercisePlan: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var unit: ExerciseUnit = .repetitions
    var sets = 3
    var target = 10
    var weight: Double = 0
    var rest = 60
    var catalogID: String?
    var isCustom: Bool?
    // A reusable exercise has its own identity, separate from its place in a routine.
    var customID: UUID?
    var muscleOverride: MuscleSelection?
    var techniqueNote: String?
    var drops: [DropStagePlan]?
    var progression: ExerciseProgression?
}

enum ExerciseBlockKind: String, Codable, CaseIterable, Identifiable {
    case superset, circuit
    var id: Self { self }
    var title: String { self == .superset ? "Суперсет" : "Круг" }
    var icon: String { self == .superset ? "link" : "arrow.clockwise" }
    var minimumExercises: Int { self == .superset ? 2 : 3 }
    func accepts(_ count: Int) -> Bool { self == .superset ? count == 2 : count >= minimumExercises }
}

struct ExerciseBlock: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: ExerciseBlockKind
    var exerciseIDs: [UUID]
    var rest = 60
}

extension Array where Element == ExerciseBlock {
    func available(for ids: [UUID]) -> [ExerciseBlock] {
        var assigned: Set<UUID> = []
        var result: [ExerciseBlock] = []
        for var block in self {
            let members = Set(block.exerciseIDs)
            block.exerciseIDs = ids.filter { members.contains($0) && !assigned.contains($0) }
            guard block.kind.accepts(block.exerciseIDs.count) else { continue }
            assigned.formUnion(block.exerciseIDs)
            result.append(block)
        }
        return result
    }
}

struct Routine: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var kind: WorkoutKind = .strength
    var weekday: Weekday? = nil
    var exercises: [ExercisePlan] = []
    var blocks: [ExerciseBlock]?
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
    var round: Int?
    var dropStage: Int?
}

struct LoggedExercise: Identifiable, Codable, Equatable {
    var id = UUID()
    var plan: ExercisePlan
    var sets: [LoggedSet]

    init(_ plan: ExercisePlan) {
        self.plan = plan
        self.sets = (0..<max(0, plan.sets)).flatMap { offset in
            let round = offset + 1
            let first = LoggedSet(value: plan.target, weight: plan.weight, round: round)
            let drops = (plan.drops ?? []).enumerated().map { index, stage in
                LoggedSet(value: stage.repetitions, weight: stage.weight, round: round, dropStage: index + 1)
            }
            return [first] + drops
        }
    }

    var completedRounds: Int {
        Set(sets.enumerated().compactMap { index, set in set.complete ? set.round ?? index + 1 : nil }).count
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
    var restOriginSetID: UUID?
    var pulse: [PulsePoint]?
    var blocks: [ExerciseBlock]?
    var notes = ""

    init(routine: Routine?, now: Date) {
        let template = routine ?? .quick
        routineID = routine?.id
        name = template.name
        kind = template.kind
        startedAt = now
        exercises = template.exercises.map(LoggedExercise.init)
        blocks = template.blocks
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
    var pulse: [PulsePoint]?
    var fromWatch: Bool?
    var blocks: [ExerciseBlock]?

    var awaitsHealthExport: Bool { !healthExported && healthExportRequestedAt != nil }

    var duration: Int { max(1, Int(endedAt.timeIntervalSince(startedAt))) }
    var sets: Int { exercises.reduce(0) { $0 + $1.completedRounds } }

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
        pulse = draft.pulse
        blocks = draft.blocks?.available(for: draft.exercises.map(\.plan.id))
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
    var nutritionGoals: NutritionGoals?
    var sleepGoalMinutes: Int?
    var recoveryCheckIns: [RecoveryCheckIn]?
    var customExercises: [ExercisePlan]?

    /// Includes exercises created before the personal library existed. Historical
    /// plans remain untouched; the first successful write retains their definitions.
    var savedExercises: [ExercisePlan] {
        let embedded = (activeWorkout?.exercises.map(\.plan) ?? []) +
            programs.flatMap(\.routines).flatMap(\.exercises) +
            records.sorted { $0.endedAt > $1.endedAt }.flatMap(\.exercises).map(\.plan)
        var seen: Set<String> = []
        return ((customExercises ?? []) + embedded).filter {
            $0.isUserDefined && !$0.name.trimmed.isEmpty && seen.insert($0.historyKey).inserted
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    mutating func retainCustomExercises() { customExercises = savedExercises }

    mutating func rememberExercise(_ plan: ExercisePlan) {
        guard plan.isUserDefined, !plan.name.trimmed.isEmpty else { return }
        var library = customExercises ?? savedExercises
        library.removeAll { $0.historyKey == plan.historyKey }
        library.append(plan)
        customExercises = library
    }

    var sleepGoal: Int {
        guard let sleepGoalMinutes, RecoverySnapshot.sleepGoalRange.contains(sleepGoalMinutes) else {
            return RecoverySnapshot.defaultSleepMinutes
        }
        return sleepGoalMinutes
    }

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
