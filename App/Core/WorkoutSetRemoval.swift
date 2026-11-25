import Foundation

struct RemovedWorkoutSets: Equatable {
    struct Entry: Equatable {
        let index: Int
        let set: LoggedSet
    }
    let workoutID: UUID
    let exerciseID: UUID
    let entries: [Entry]
}

extension ActiveWorkout {
    @discardableResult mutating func removeSet(exerciseID: UUID, setID: UUID) -> RemovedWorkoutSets? {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }),
              let selected = exercises[index].sets.first(where: { $0.id == setID }) else { return nil }
        // Materialize legacy round numbers before removing an item: enumeration
        // must not move a surviving circuit exercise into another round.
        let rounds = Dictionary(uniqueKeysWithValues: exercises[index].steps.map { ($0.id, $0.round) })
        for offset in exercises[index].sets.indices where exercises[index].sets[offset].round == nil {
            exercises[index].sets[offset].round = rounds[exercises[index].sets[offset].id]
        }
        let round = rounds[setID]
        let removed = exercises[index].sets.enumerated().compactMap { offset, set -> RemovedWorkoutSets.Entry? in
            let matches = selected.dropStage == nil ? set.round == round : set.id == setID
            return matches ? .init(index: offset, set: set) : nil
        }
        let ids = Set(removed.map { $0.set.id })
        exercises[index].sets.removeAll { ids.contains($0.id) }
        if let origin = restOriginSetID, ids.contains(origin) { restUntil = nil; restOriginSetID = nil }
        return .init(workoutID: id, exerciseID: exerciseID, entries: removed)
    }

    @discardableResult mutating func restoreSets(_ removed: RemovedWorkoutSets) -> Bool {
        guard id == removed.workoutID, let index = exercises.firstIndex(where: { $0.id == removed.exerciseID }) else { return false }
        var changed = false
        for entry in removed.entries.sorted(by: { $0.index < $1.index }) where !exercises[index].sets.contains(where: { $0.id == entry.set.id }) {
            exercises[index].sets.insert(entry.set, at: min(entry.index, exercises[index].sets.count))
            changed = true
        }
        return changed
    }
}

extension JournalStore {
    @discardableResult func removeWorkoutSet(exerciseID: UUID, setID: UUID) -> RemovedWorkoutSets? {
        var removed: RemovedWorkoutSets?
        guard change({ journal in
            guard var workout = journal.activeWorkout else { return }
            removed = workout.removeSet(exerciseID: exerciseID, setID: setID)
            journal.activeWorkout = workout
        }) else { return nil }
        if let removed { removedWorkoutSets = removed }
        return removed
    }

    @discardableResult func restoreWorkoutSets(_ removed: RemovedWorkoutSets) -> Bool {
        var restored = false
        let saved = change { journal in
            guard var workout = journal.activeWorkout else { return }
            restored = workout.restoreSets(removed)
            journal.activeWorkout = workout
        }
        if saved && restored { removedWorkoutSets = nil }
        return saved && restored
    }
}
