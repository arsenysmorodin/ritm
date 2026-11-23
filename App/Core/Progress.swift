import Foundation

struct ExerciseProgress: Identifiable {
    let id: String
    var name: String
    let unit: ExerciseUnit
    var points: [Point]

    struct Point: Identifiable {
        let id: UUID
        let date: Date
        var sets: Int
        var total: Int
        var bestWeight: Double
        var volume: Double
    }

    var bestWeight: Double { points.map(\.bestWeight).max() ?? 0 }
    var totalSets: Int { points.reduce(0) { $0 + $1.sets } }

    static func summarize(_ records: [WorkoutRecord]) -> [ExerciseProgress] {
        var groups: [String: ExerciseProgress] = [:]
        for record in records.sorted(by: { $0.startedAt < $1.startedAt }) {
            var session: [String: Point] = [:]
            for exercise in record.exercises {
                let plan = exercise.plan
                let id = plan.historyKey
                let sets = exercise.sets.filter(\.complete)
                guard !sets.isEmpty else { continue }
                if groups[id] == nil {
                    groups[id] = ExerciseProgress(id: id, name: plan.name, unit: plan.unit, points: [])
                }
                groups[id]?.name = plan.name
                var point = session[id] ?? Point(id: record.id, date: record.startedAt, sets: 0, total: 0, bestWeight: 0, volume: 0)
                point.sets += exercise.completedRounds
                for set in sets {
                    point.total += set.value
                    point.bestWeight = max(point.bestWeight, set.weight)
                    if plan.unit == .repetitions { point.volume += set.weight * Double(set.value) }
                }
                session[id] = point
            }
            for (id, point) in session { groups[id]?.points.append(point) }
        }
        return groups.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

extension ExercisePlan {
    var historyKey: String {
        let key = isCustom == true ? "user:\(customID ?? id)" :
            ExerciseCatalog.find(self)?.id ?? "custom:\(ExerciseCatalog.normalize(name))"
        return key + ":\(unit.rawValue)"
    }

    var isUserDefined: Bool { isCustom == true || ExerciseCatalog.find(self) == nil }

    func placedInRoutine(id placementID: UUID = UUID()) -> Self {
        var placed = self
        if isCustom == true { placed.customID = customID ?? id }
        placed.id = placementID
        return placed
    }
}

struct PreviousSet {
    let value: Int
    let weight: Double

    static func find(for step: WorkoutStep, in workout: ActiveWorkout, records: [WorkoutRecord]) -> Self? {
        guard let plan = workout.exercises.first(where: { $0.id == step.exerciseID })?.plan else { return nil }
        let key = plan.historyKey
        for record in records.sorted(by: { $0.endedAt > $1.endedAt }) where record.endedAt <= workout.startedAt {
            var matching = record.exercises.filter { $0.plan.historyKey == key }
            if let samePlan = matching.firstIndex(where: { $0.plan.id == plan.id }) {
                let exercise = matching.remove(at: samePlan)
                matching.insert(exercise, at: 0)
            }
            for exercise in matching {
                let candidates = exercise.steps.filter {
                    $0.set.complete && $0.set.dropStage == step.set.dropStage &&
                    (1...3600).contains($0.set.value) && (0...500).contains($0.set.weight)
                }
                if let match = candidates.first(where: { $0.round == step.round }) ?? candidates.last {
                    return Self(value: match.set.value, weight: match.set.weight)
                }
            }
        }
        return nil
    }
}

struct ExerciseProgression: Codable, Equatable {
    let lowerReps: Int
    let upperReps: Int
    let weightIncrement: Double?

    var isValid: Bool {
        (1...3600).contains(lowerReps) && (lowerReps...3600).contains(upperReps) &&
            (weightIncrement.map { (0.01...500).contains($0) } ?? true)
    }
}

enum NextExerciseGoal {
    static func find(for step: WorkoutStep, in workout: ActiveWorkout, records: [WorkoutRecord]) -> PreviousSet? {
        guard !step.set.complete, step.set.dropStage == nil, step.unit == .repetitions,
              let plan = workout.exercises.first(where: { $0.id == step.exerciseID })?.plan,
              let progression = plan.progression, progression.isValid, plan.sets > 0 else { return nil }

        let key = plan.historyKey
        for record in records.sorted(by: { $0.endedAt > $1.endedAt }) where record.endedAt <= workout.startedAt {
            let matches = record.exercises.filter { $0.plan.historyKey == key }
            guard let exercise = matches.first(where: { $0.plan.id == plan.id }) ?? matches.first else { continue }

            let rounds = exercise.steps.filter {
                $0.set.dropStage == nil && $0.set.complete && (1...3600).contains($0.set.value) &&
                    (0...500).contains($0.set.weight) && (1...plan.sets).contains($0.round)
            }
            guard Set(rounds.map(\.round)).count == plan.sets,
                  let previous = rounds.first(where: { $0.round == step.round })?.set else { return nil }

            let atTop = rounds.allSatisfy {
                $0.set.value >= progression.upperReps && abs($0.set.weight - previous.weight) < 0.00001
            }
            if atTop, previous.weight > 0, let increment = progression.weightIncrement {
                let nextWeight = ((previous.weight + increment) * 100).rounded() / 100
                if nextWeight <= 500, nextWeight > previous.weight,
                   (plan.drops ?? []).allSatisfy({ $0.weight < nextWeight }) {
                    return PreviousSet(value: progression.lowerReps, weight: nextWeight)
                }
            }
            guard previous.value < progression.upperReps,
                  (plan.drops ?? []).allSatisfy({ $0.weight < previous.weight }) else { return nil }
            return PreviousSet(value: previous.value + 1, weight: previous.weight)
        }
        return nil
    }
}

struct MuscleWeek: Identifiable {
    struct Contribution: Identifiable {
        let id: String
        var name: String
        var primary = 0
        var secondary = 0
    }

    var id: Muscle { muscle }
    let muscle: Muscle
    let exercises: [Contribution]
    var primary: Int { exercises.reduce(0) { $0 + $1.primary } }
    var secondary: Int { exercises.reduce(0) { $0 + $1.secondary } }

    static func summarize(_ records: [WorkoutRecord], in interval: DateInterval) -> [MuscleWeek] {
        var byMuscle: [Muscle: [String: Contribution]] = [:]
        for record in records where record.startedAt >= interval.start && record.startedAt < interval.end {
            for exercise in record.exercises {
                let rounds = exercise.completedRounds
                guard rounds > 0 else { continue }
                let key = exercise.plan.historyKey
                let muscles = exercise.plan.muscles
                let primary = Set(muscles.primary)
                let secondary = Set(muscles.secondary).subtracting(primary)
                for muscle in primary.union(secondary) {
                    var contribution = byMuscle[muscle]?[key] ?? Contribution(id: key, name: exercise.plan.name)
                    if primary.contains(muscle) { contribution.primary += rounds } else { contribution.secondary += rounds }
                    byMuscle[muscle, default: [:]][key] = contribution
                }
            }
        }
        return Muscle.allCases.compactMap { muscle in
            guard let exercises = byMuscle[muscle], !exercises.isEmpty else { return nil }
            return MuscleWeek(muscle: muscle, exercises: exercises.values.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            })
        }.sorted { ($0.primary, $0.secondary, $0.muscle.rawValue) > ($1.primary, $1.secondary, $1.muscle.rawValue) }
    }
}
