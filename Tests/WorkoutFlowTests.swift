import Foundation
import Testing
@testable import RitmCore

struct WorkoutFlowTests {
    @Test @MainActor func previousSetReusesMatchingRoundsAndDropStagesWithoutCompletingTheSet() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "RitmPreviousSetTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "journal.json")
        let store = JournalStore(url: file)
        let press = ExercisePlan(name: "Жим", sets: 2, target: 10, weight: 16, isCustom: true,
                                 drops: [.init(repetitions: 8, weight: 12)])
        let unrelated = ExercisePlan(name: press.name, target: 30, weight: 4, isCustom: true)
        let earlier = Date.now.addingTimeInterval(-600)
        var old = ActiveWorkout(routine: Routine(name: "Силовая", exercises: [press]), now: earlier)
        old.exercises[0].sets[0] = LoggedSet(value: 11, weight: 18, complete: true, round: 1)
        old.exercises[0].sets[1] = LoggedSet(value: 9, weight: 0, complete: true, round: 1, dropStage: 1)
        old.exercises[0].sets[2] = LoggedSet(value: 7, weight: 20, complete: true, round: 2)
        var different = ActiveWorkout(routine: Routine(name: "Другая", exercises: [unrelated]), now: earlier.addingTimeInterval(120))
        different.exercises[0].sets[0].complete = true
        let records = [WorkoutRecord(different, endedAt: earlier.addingTimeInterval(210)),
                       WorkoutRecord(old, endedAt: earlier.addingTimeInterval(90))]
        let routine = Routine(name: old.name, exercises: [press])
        #expect(store.change { $0.records = records })
        #expect(store.start(routine))
        let draft = try #require(store.journal.activeWorkout)
        let steps = draft.exercises[0].steps

        let first = try #require(PreviousSet.find(for: steps[0], in: draft, records: records))
        let second = try #require(PreviousSet.find(for: steps[2], in: draft, records: records))
        let drop = try #require(PreviousSet.find(for: steps[3], in: draft, records: records))
        #expect(first.value == 11 && first.weight == 18)
        #expect(second.value == 7 && second.weight == 20)
        #expect(drop.value == 9 && drop.weight == 0)
        #expect(store.applyPreviousSet(drop, to: steps[3]))
        let saved = try #require(JournalFile.load(file).activeWorkout?.exercises[0].sets[3])
        #expect(saved.id == steps[3].id && saved.value == 9 && saved.weight == 0)
        #expect(!saved.complete && saved.round == 2 && saved.dropStage == 1)
        #expect(store.journal.activeWorkout?.restUntil == nil)
    }

    @Test func everyCatalogExerciseHasAnIllustratedPosition() {
        let missing = ExerciseCatalog.all.filter { ExerciseTechnique.frames(for: $0.id).isEmpty }.map(\.id)
        #expect(missing.isEmpty)
    }

    @Test @MainActor func supersetContinuesThroughDropStagesBeforeResting() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "RitmSupersetTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "journal.json")
        let store = JournalStore(url: file)
        let now = Date.now
        let press = ExercisePlan(name: "Жим", target: 10, weight: 16,
            drops: [.init(repetitions: 8, weight: 11), .init(repetitions: 5, weight: 8)])
        let row = ExercisePlan(name: "Тяга", target: 8)
        var routine = Routine(name: "Верх", exercises: [press, row])
        routine.save(ExerciseBlock(kind: .superset, exerciseIDs: [row.id, press.id], rest: 75), rounds: 2)

        #expect(store.start(routine, at: now))
        let section = try #require(store.journal.activeWorkout?.sections.first)
        #expect(section.rounds.map(\.id) == [1, 2])
        #expect(section.rounds[0].steps.map(\.name) == ["Жим", "Жим", "Жим", "Тяга"])
        #expect(section.rounds[0].steps.map(\.set.dropStage) == [nil, 1, 2, nil])
        for step in section.rounds[0].steps.dropLast() {
            #expect(store.watchSnapshot?.next?.setID == step.id)
            store.toggleSet(exerciseID: step.exerciseID, setID: step.id, at: now)
            #expect(store.journal.activeWorkout?.restUntil == nil)
        }
        let last = try #require(section.rounds[0].steps.last)
        store.toggleSet(exerciseID: last.exerciseID, setID: last.id, at: now)
        #expect(store.journal.activeWorkout?.restUntil == now.addingTimeInterval(75))
        #expect(store.watchSnapshot?.next?.setID == section.rounds[1].steps.first?.id)

        let record = try #require(store.finish(at: now.addingTimeInterval(120)))
        #expect(try JournalFile.load(file).records.first?.blocks?.first?.kind == .superset)
        #expect(record.sets == 2)
        let result = try #require(ExerciseProgress.summarize([record]).first { $0.name == "Жим" }?.points.first)
        #expect(result.sets == 1)
        #expect(result.total == 23)
        #expect(result.volume == 288)
    }

    @Test func circleRunsEachExercisePerRoundAndRemovesInvalidGroups() throws {
        let exercises = ["Присед", "Мост", "Планка", "Одиночное"].map { ExercisePlan(name: $0) }
        var routine = Routine(name: "Круговая", exercises: exercises)
        routine.save(ExerciseBlock(kind: .circuit, exerciseIDs: exercises.prefix(3).map(\.id), rest: 45), rounds: 2)
        let workout = ActiveWorkout(routine: routine, now: .now)
        let circuit = try #require(workout.sections.first)
        #expect(circuit.rounds.map { $0.steps.map(\.name) } == [
            ["Присед", "Мост", "Планка"], ["Присед", "Мост", "Планка"]
        ])
        #expect(workout.sections.last?.exercises.first?.plan.name == "Одиночное")
        routine.removeExercises(at: IndexSet(integer: 1))
        #expect(routine.exerciseBlocks.isEmpty)
        #expect(ActiveWorkout(routine: routine, now: .now).sections.count == 3)
    }

    @Test func customMusclesRoundTripAndOverrideAnIdenticallyNamedPreset() throws {
        let old = try JSONDecoder().decode(ExercisePlan.self, from: Data("""
        {"id":"1D74222C-557B-4F61-86A1-085EDAEB3E48","name":"Приседания",
         "unit":"repetitions","sets":3,"target":12,"weight":0,"rest":60}
        """.utf8))
        #expect(old.muscles.primary.contains(.quads))
        #expect(ExerciseCatalog.find(old)?.id == "squat")

        var custom = ExercisePlan(name: old.name, isCustom: true)
        custom.muscleOverride = MuscleSelection(primary: [.adductors], secondary: [.glutes, .calves])
        let saved = try JSONDecoder().decode(ExercisePlan.self, from: JSONEncoder().encode(custom))
        #expect(ExerciseCatalog.find(saved) == nil)
        #expect(saved.muscles == custom.muscleOverride)
        let day = MuscleSelection.combined([saved.muscles, old.muscles])
        #expect(day.primary.contains(.adductors))
        #expect(day.primary.contains(.glutes))
        #expect(day.secondary == [.abs, .calves])
    }
}
