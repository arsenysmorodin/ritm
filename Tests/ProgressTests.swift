import Foundation
import Testing
@testable import RitmCore

struct ProgressTests {
    @Test func combinesLegacyAndCatalogExerciseSetsWithoutMixingUnits() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let legacy = ExercisePlan(name: " ТЯГА  ГАНТЕЛЕЙ ", sets: 2, target: 10, weight: 6)
        let catalog = ExercisePlan(name: "Тяга в наклоне", sets: 1, target: 8, weight: 10, catalogID: "dumbbell-row")
        let timed = ExercisePlan(name: catalog.name, unit: .seconds, sets: 1, target: 35, catalogID: catalog.catalogID)
        var first = ActiveWorkout(routine: Routine(name: "Силовая", exercises: [legacy]), now: start)
        first.exercises[0].sets[0].complete = true
        var second = ActiveWorkout(routine: Routine(name: "Силовая", exercises: [catalog, timed]), now: start.addingTimeInterval(3600))
        second.exercises[0].sets[0].complete = true
        second.exercises[1].sets[0].complete = true
        let records = [WorkoutRecord(second, endedAt: second.startedAt.addingTimeInterval(90)), WorkoutRecord(first, endedAt: start.addingTimeInterval(60))]

        let result = ExerciseProgress.summarize(records)
        let reps = try #require(result.first { $0.unit == .repetitions })
        let seconds = try #require(result.first { $0.unit == .seconds })
        #expect(result.count == 2)
        #expect(reps.points.map(\.total) == [10, 8])
        #expect(reps.points.map(\.volume) == [60, 80])
        #expect(reps.bestWeight == 10)
        #expect(seconds.points.map(\.total) == [35])
        #expect(seconds.points.map(\.volume) == [0])
    }

    @Test @MainActor func keepsWatchMarksIdempotentAndClipsDelayedPulseToTheSession() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "RitmWatchTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "journal.json")
        let store = JournalStore(url: file)
        let now = Date.now.addingTimeInterval(-120)
        let routine = try #require(store.journal.activeProgram?.routines.first)
        #expect(store.change { $0.healthEnabled = true })
        #expect(store.start(routine, at: now))
        let snapshot = try #require(store.watchSnapshot)
        let next = try #require(snapshot.next)
        let mark = WatchEvent.mark(workout: snapshot.workoutID, exercise: next.exerciseID, set: next.setID)
        #expect(store.receiveWatch(mark))
        #expect(store.receiveWatch(mark))
        #expect(store.journal.activeWorkout?.marked == 1)
        let finished = try #require(store.finish(at: now.addingTimeInterval(60)))
        #expect(!store.receiveWatch(mark))
        let valid = PulsePoint(date: now.addingTimeInterval(15), bpm: 110)
        let late = PulsePoint(date: now.addingTimeInterval(90), bpm: 170)
        #expect(store.receiveWatch(.pulse(workout: finished.id, points: [valid, valid, late])))
        #expect(try JournalFile.load(file).records.first?.pulse == [valid])
    }

    @Test @MainActor func importsStandaloneWatchWorkoutOnceWithoutRequestingAnotherHealthExport() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "RitmWatchImportTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JournalStore(url: directory.appending(path: "journal.json"))
        let start = Date.now.addingTimeInterval(-120)
        let activity = WatchActivity(id: UUID(), kind: "strength", startedAt: start, endedAt: start.addingTimeInterval(60), pulse: [])
        #expect(store.receiveWatch(.finished(activity)))
        #expect(store.receiveWatch(.finished(activity)))
        #expect(store.journal.records.count == 1)
        #expect(store.journal.records.first?.fromWatch == true)
        #expect(store.journal.records.first?.awaitsHealthExport == false)
    }

    @Test func widgetRollsOverOnMondayAndSkipsACompletedRoutine() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Moscow"))
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9)))
        let sunday = monday.addingTimeInterval(-12 * 3600)
        let first = UUID()
        let second = UUID()
        let summary = WidgetSnapshot(activeWorkout: nil, completedSets: 0, totalSets: 0,
            routines: [.init(id: first, title: "Корпус", weekday: 2), .init(id: second, title: "Ноги", weekday: nil)],
            completions: [.init(routineID: nil, date: sunday), .init(routineID: first, date: monday)], weeklyGoal: 3)
        #expect(summary.week(at: sunday, calendar: calendar) == [0, 0, 0, 0, 0, 0, 1])
        #expect(summary.week(at: monday, calendar: calendar) == [1, 0, 0, 0, 0, 0, 0])
        #expect(summary.suggestion(at: monday, calendar: calendar) == "Ноги")
    }
}
