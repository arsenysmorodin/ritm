import Foundation

struct WeightPoint: Identifiable, Equatable {
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
        let key = isCustom == true ? "user:\(id)" :
            ExerciseCatalog.find(self)?.id ?? "custom:\(ExerciseCatalog.normalize(name))"
        return key + ":\(unit.rawValue)"
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
