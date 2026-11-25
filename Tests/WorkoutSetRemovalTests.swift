import Foundation
import Testing
@testable import RitmCore

@Test func deletingADropHeadRemovesItsStagesButDeletingAStageKeepsTheHead() throws {
    let plan = ExercisePlan(name: "Жим", sets: 2, drops: [.init(repetitions: 8, weight: 12), .init(repetitions: 6, weight: 8)])
    var workout = ActiveWorkout(routine: Routine(name: "Тест", exercises: [plan]), now: .now)
    let exercise = workout.exercises[0]
    let deletion = workout.removeSet(exerciseID: exercise.id, setID: exercise.sets[0].id)
    let removed = try #require(deletion)
    #expect(removed.entries.count == 3)
    #expect(workout.exercises[0].steps.allSatisfy { $0.round == 2 })
    let restored = workout.restoreSets(removed)
    let replayed = workout.restoreSets(removed)
    #expect(restored)
    #expect(!replayed)
    #expect(workout.exercises[0].sets.count == 6)
    let stageDeletion = workout.removeSet(exerciseID: exercise.id, setID: exercise.sets[1].id)
    let stage = try #require(stageDeletion)
    #expect(stage.entries.count == 1)
    #expect(workout.exercises[0].sets.contains { $0.id == exercise.sets[0].id })
}

@Test func deletingACircuitSetDoesNotRenumberOtherRoundsAndUndoKeepsNewEdits() throws {
    let plans = [ExercisePlan(name: "Приседания", sets: 3), ExercisePlan(name: "Отжимания", sets: 3)]
    var workout = ActiveWorkout(routine: Routine(name: "Суперсет", exercises: plans,
        blocks: [.init(kind: .superset, exerciseIDs: plans.map(\.id))]), now: .now)
    // Old journals may not contain explicit round numbers.
    for index in workout.exercises[0].sets.indices { workout.exercises[0].sets[index].round = nil }
    let exercise = workout.exercises[0], remainingID = exercise.sets[2].id
    let deletion = workout.removeSet(exerciseID: exercise.id, setID: exercise.sets[1].id)
    let removed = try #require(deletion)
    #expect(workout.exercises[0].steps.map(\.round) == [1, 3])
    #expect(workout.sections[0].rounds.map(\.id) == [1, 2, 3])
    workout.exercises[0].sets[1].complete = true
    let restored = workout.restoreSets(removed)
    #expect(restored)
    #expect(workout.exercises[0].sets.first(where: { $0.id == remainingID })?.complete == true)
    #expect(workout.exercises[0].sets.map(\.id) == exercise.sets.map(\.id))
}

@Test func deletingOnlyTheRestOriginCancelsItsTimer() throws {
    var workout = ActiveWorkout(routine: Routine(name: "Тест", exercises: [ExercisePlan(name: "Приседания", sets: 3)]), now: .now)
    let exercise = workout.exercises[0], deadline = Date.now.addingTimeInterval(90)
    workout.restUntil = deadline; workout.restOriginSetID = exercise.sets[0].id
    let future = workout.removeSet(exerciseID: exercise.id, setID: exercise.sets[2].id)
    _ = try #require(future)
    #expect(workout.restUntil == deadline)
    let origin = workout.removeSet(exerciseID: exercise.id, setID: exercise.sets[0].id)
    _ = try #require(origin)
    #expect(workout.restUntil == nil)
    #expect(workout.restOriginSetID == nil)
}

@Test @MainActor func watchDeletionIsIdempotentAndSharesThePhoneUndo() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "ritm-watch-delete-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = JournalStore(url: folder.appending(path: "journal.json"))
    #expect(store.start(Routine(name: "Тест", exercises: [ExercisePlan(name: "Приседания", sets: 3)])))
    let workout = try #require(store.journal.activeWorkout)
    let step = try #require(workout.nextStep)
    let command = WatchEvent.removeSet(workout: workout.id, exercise: step.exerciseID, set: step.id)
    #expect(!store.receiveWatch(.removeSet(workout: UUID(), exercise: step.exerciseID, set: step.id)))
    #expect(store.receiveWatch(command))
    #expect(store.receiveWatch(command))
    #expect(store.journal.activeWorkout?.total == 2)
    let undo = try #require(store.removedWorkoutSets)
    #expect(store.restoreWorkoutSets(undo))
    #expect(store.removedWorkoutSets == nil)
    #expect(store.journal.activeWorkout?.total == 3)
    let reloaded = JournalStore(url: folder.appending(path: "journal.json"))
    #expect(reloaded.journal.activeWorkout?.exercises[0].sets.map(\.id) == workout.exercises[0].sets.map(\.id))
}
