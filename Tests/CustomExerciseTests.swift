import Foundation
import Testing
@testable import RitmCore

struct CustomExerciseTests {
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "RitmLibrary-\(UUID())/journal.json")
    }

    @Test @MainActor func recoversOldExercisesAndRetainsThemAfterDeletingTheirProgram() throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let manual = ExercisePlan(name: "Моя тяга", isCustom: true, muscleOverride: .init(primary: [.lats]))
        let legacy = ExercisePlan(name: "Старое движение", muscleOverride: .init(primary: [.quads]))
        let program = Program(name: "Личная", routines: [Routine(name: "День", exercises: [manual, legacy])])
        var journal = Journal.fresh()
        journal.programs = [program]
        try JournalFile.save(journal, to: url)
        let store = JournalStore(url: url)
        #expect(store.journal.customExercises == nil)
        #expect(store.journal.savedExercises.count == 2)
        store.deleteProgram(program.id)
        let reopened = JournalStore(url: url)
        #expect(reopened.journal.programs.isEmpty)
        #expect(Set(reopened.journal.savedExercises.map(\.historyKey)) == [manual.historyKey, legacy.historyKey])
        #expect(reopened.journal.savedExercises.first { $0.id == manual.id }?.muscles.primary == [.lats])
    }

    @Test @MainActor func reusingAnExerciseCombinesProgressAndPreviousSetsAcrossDifferentDays() throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = JournalStore(url: url)
        let plan = ExercisePlan(name: "Тяга у стены", sets: 1, target: 12, weight: 8, isCustom: true,
                                muscleOverride: .init(primary: [.lats], secondary: [.biceps]))
        #expect(store.saveExercise(plan))
        let start = Date.now.addingTimeInterval(-7200)
        #expect(store.start(Routine(name: "Первый день", exercises: [plan]), at: start))
        #expect(store.updateWorkout { $0.exercises[0].sets[0].complete = true })
        let first = try #require(store.finish(at: start.addingTimeInterval(600)))
        let reused = try #require(JournalStore(url: url).journal.savedExercises.first).placedInRoutine()
        #expect(reused.id != plan.id)
        #expect(reused.historyKey == plan.historyKey)
        #expect(store.start(Routine(name: "Второй день", exercises: [reused]), at: start.addingTimeInterval(3600)))
        let active = try #require(store.journal.activeWorkout)
        let step = try #require(active.nextStep)
        let previous = try #require(PreviousSet.find(for: step, in: active, records: [first]))
        #expect(previous.value == 12 && previous.weight == 8)
        #expect(store.updateWorkout { $0.exercises[0].sets[0].complete = true })
        _ = try #require(store.finish(at: start.addingTimeInterval(4200)))
        let records = JournalStore(url: url).journal.records
        let progress = ExerciseProgress.summarize(records)
        #expect(progress.count == 1)
        #expect(progress.first?.totalSets == 2)
        #expect(progress.first?.points.map(\.volume) == [96, 96])
        let muscles = MuscleWeek.summarize(records, in: DateInterval(start: start, duration: 86400))
        #expect(muscles.first { $0.muscle == .lats }?.primary == 2)
        #expect(muscles.first { $0.muscle == .biceps }?.secondary == 2)
    }

    @Test @MainActor func standaloneExerciseSurvivesRelaunchAndBackupWithoutRewritingRecords() throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = JournalStore(url: url)
        var plan = ExercisePlan(name: "Отжимания", isCustom: true, muscleOverride: .init(primary: [.shoulders]))
        plan.techniqueNote = "С опорой на стену"
        #expect(store.saveExercise(plan))
        let reopened = JournalStore(url: url)
        #expect(reopened.journal.savedExercises == [plan])
        var edited = plan.placedInRoutine()
        edited.name = "Мои отжимания"
        #expect(reopened.saveExercise(edited))
        #expect(reopened.journal.savedExercises.count == 1)
        let backup = try JournalBackup.decode(JSONEncoder().encode(JournalBackup(journal: reopened.journal)))
        #expect(store.restore(backup))
        #expect(store.journal.savedExercises.first?.techniqueNote == plan.techniqueNote)
        #expect(store.journal.savedExercises.first?.historyKey == plan.historyKey)
        #expect(store.journal.records.isEmpty)
        #expect(plan.historyKey != ExercisePlan(name: "Отжимания").historyKey)
    }

    @Test @MainActor func retainsExercisesFoundOnlyInOldHistoryOrAnAbandonedWorkout() throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let historical = ExercisePlan(name: "Движение из архива", sets: 1, isCustom: true)
        let unfinished = ExercisePlan(name: "Моё новое движение", isCustom: true)
        var completed = ActiveWorkout(routine: Routine(name: "Архив", exercises: [historical]), now: .now.addingTimeInterval(-3600))
        completed.exercises[0].sets[0].complete = true
        var journal = Journal.fresh()
        journal.programs = []
        journal.records = [WorkoutRecord(completed, endedAt: .now.addingTimeInterval(-3000))]
        journal.activeWorkout = ActiveWorkout(routine: Routine(name: "Свободная", exercises: [unfinished]), now: .now)
        try JournalFile.save(journal, to: url)
        let store = JournalStore(url: url)
        #expect(store.journal.savedExercises.count == 2)
        #expect(store.change { $0.records = []; $0.activeWorkout = nil })
        let reopened = JournalStore(url: url)
        #expect(Set(reopened.journal.savedExercises.map(\.historyKey)) == [historical.historyKey, unfinished.historyKey])
        #expect(reopened.journal.records.isEmpty && reopened.journal.activeWorkout == nil)
    }
}
