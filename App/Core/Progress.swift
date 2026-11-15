import Foundation

struct WeightPoint: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let kilograms: Double
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
                let preset = ExerciseCatalog.find(plan)
                let id = (preset?.id ?? "custom:\(ExerciseCatalog.normalize(plan.name))") + ":\(plan.unit.rawValue)"
                let sets = exercise.sets.filter(\.complete)
                guard !sets.isEmpty else { continue }
                if groups[id] == nil {
                    groups[id] = ExerciseProgress(id: id, name: plan.name, unit: plan.unit, points: [])
                }
                groups[id]?.name = plan.name
                var point = session[id] ?? Point(id: record.id, date: record.startedAt, sets: 0, total: 0, bestWeight: 0, volume: 0)
                for set in sets {
                    point.sets += 1
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
