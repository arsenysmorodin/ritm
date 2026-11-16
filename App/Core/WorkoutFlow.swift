import Foundation

extension Routine {
    var exerciseBlocks: [ExerciseBlock] { (blocks ?? []).available(for: exercises.map(\.id)) }

    mutating func removeExercises(at indices: IndexSet) {
        for index in indices.reversed() { exercises.remove(at: index) }
        blocks = exerciseBlocks
    }

    mutating func save(_ block: ExerciseBlock, rounds: Int) {
        var updated = exerciseBlocks
        if let index = updated.firstIndex(where: { $0.id == block.id }) {
            updated[index] = block
        } else {
            updated.append(block)
        }
        blocks = updated
        for index in exercises.indices where block.exerciseIDs.contains(exercises[index].id) {
            exercises[index].sets = rounds
        }
    }
}

struct WorkoutStep: Identifiable {
    var id: UUID { self.set.id }
    let exerciseID: UUID
    let name: String
    let unit: ExerciseUnit
    let round: Int
    let set: LoggedSet

    var title: String {
        if let stage = set.dropStage { return "Дроп \(stage)" }
        return "Подход \(round)"
    }
}

struct WorkoutRest: Equatable, Hashable, Codable {
    let workoutID: UUID
    let endsAt: Date
}

struct WorkoutRound: Identifiable {
    let id: Int
    let steps: [WorkoutStep]
}

struct WorkoutSection: Identifiable {
    let id: UUID
    let block: ExerciseBlock?
    let exercises: [LoggedExercise]

    var rounds: [WorkoutRound] {
        let byRound = Dictionary(grouping: exercises.flatMap(\.steps), by: \.round)
        return byRound.sorted { $0.key < $1.key }.map { WorkoutRound(id: $0.key, steps: $0.value) }
    }

    var rest: Int { block?.rest ?? exercises.first?.plan.rest ?? 0 }
}

extension LoggedExercise {
    var steps: [WorkoutStep] {
        sets.enumerated().map { index, set in
            WorkoutStep(exerciseID: id, name: plan.name, unit: plan.unit, round: set.round ?? index + 1, set: set)
        }
    }

    mutating func appendRound() {
        let round = (steps.last?.round ?? 0) + 1
        let last = sets.last { $0.dropStage == nil }
        sets.append(LoggedSet(value: last?.value ?? plan.target, weight: last?.weight ?? plan.weight, round: round))
        for (index, stage) in (plan.drops ?? []).enumerated() {
            sets.append(LoggedSet(value: stage.repetitions, weight: stage.weight, round: round, dropStage: index + 1))
        }
    }
}

extension ActiveWorkout {
    var rest: WorkoutRest? {
        restUntil.map { WorkoutRest(workoutID: id, endsAt: $0) }
    }

    var sections: [WorkoutSection] {
        let visibleBlocks = (blocks ?? []).available(for: exercises.map(\.plan.id))
        var rendered: Set<UUID> = []
        var result: [WorkoutSection] = []
        for exercise in exercises {
            if let block = visibleBlocks.first(where: { $0.exerciseIDs.contains(exercise.plan.id) }) {
                guard rendered.insert(block.id).inserted else { continue }
                let group = exercises.filter { block.exerciseIDs.contains($0.plan.id) }
                result.append(WorkoutSection(id: block.id, block: block, exercises: group))
            } else {
                result.append(WorkoutSection(id: exercise.id, block: nil, exercises: [exercise]))
            }
        }
        return result
    }

    var nextStep: WorkoutStep? {
        for section in sections {
            for round in section.rounds {
                if let step = round.steps.first(where: { !$0.set.complete }) { return step }
            }
        }
        return nil
    }

    func restAfter(setID: UUID) -> Int {
        for section in sections {
            if let round = section.rounds.first(where: { $0.steps.contains { $0.id == setID } }) {
                return round.steps.allSatisfy(\.set.complete) ? section.rest : 0
            }
        }
        return 0
    }
}
