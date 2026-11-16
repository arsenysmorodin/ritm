import Foundation
import Testing
@testable import RitmCore

struct JournalTests {
    private let time = Date(timeIntervalSince1970: 1_786_359_600)

    @Test @MainActor func testResumeAndFinishPersistsOnlyMarkedSets() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = JournalStore(url: file)
        let original = try #require(store.journal.activeProgram?.routines.first)
        #expect(store.start(original, at: time))
        let first = try #require(store.journal.activeWorkout?.exercises.first)
        let firstSet = try #require(first.sets.first)
        #expect(store.updateWorkout { draft in
            draft.exercises[0].sets[0].value = 14
            draft.exercises[0].sets[0].weight = 2.5
            draft.notes = "На коврике"
        })
        store.toggleSet(exerciseID: first.id, setID: firstSet.id, at: time.addingTimeInterval(5))
        let reopened = JournalStore(url: file)
        #expect(reopened.start(nil, at: time.addingTimeInterval(10)))
        #expect(reopened.journal.activeWorkout?.marked == 1)
        #expect(reopened.journal.activeWorkout?.name == original.name)
        #expect(reopened.journal.activeWorkout?.secondsLeft(at: time.addingTimeInterval(20)) == 45)
        #expect(reopened.journal.activeWorkout?.secondsLeft(at: time.addingTimeInterval(90)) == 0)
        let finished = try #require(reopened.finish(at: time.addingTimeInterval(120)))
        #expect(finished.sets == 1)
        #expect(finished.exercises.count == 1)
        #expect(finished.exercises.first?.sets.first?.value == 14)
        #expect(finished.exercises.first?.sets.first?.weight == 2.5)
        #expect(finished.notes == "На коврике")
        #expect(finished.duration == 120)
        #expect(reopened.finish() == nil)
        let stored = try JournalFile.load(file)
        #expect(stored.activeWorkout == nil)
        #expect(stored.records == [finished])
    }

    @Test @MainActor func testCorruptJournalIsNotOverwrittenAndCanBeReopened() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let invalid = Data("invalid journal".utf8)
        try invalid.write(to: file)
        let store = JournalStore(url: file)
        #expect(!store.isReadable)
        #expect(!store.start(nil))
        #expect(try Data(contentsOf: file) == invalid)
        try JournalFile.save(.fresh(), to: file)
        store.reload()
        #expect(store.isReadable)
        #expect(store.start(nil))
    }

    @Test @MainActor func testFinishingPersistsHealthExportRequestOnlyWhenEnabled() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = JournalStore(url: file)
        let routine = try #require(store.journal.activeProgram?.routines.first)

        #expect(store.start(routine, at: time))
        #expect(store.updateWorkout { $0.exercises[0].sets[0].complete = true })
        let local = try #require(store.finish(at: time.addingTimeInterval(30)))
        #expect(!local.awaitsHealthExport)

        #expect(store.change { $0.healthEnabled = true })
        #expect(store.start(routine, at: time.addingTimeInterval(60)))
        #expect(store.updateWorkout { $0.exercises[0].sets[0].complete = true })
        let completed = try #require(store.finish(at: time.addingTimeInterval(120)))

        let stored = try JournalFile.load(file)
        #expect(stored.records.filter(\.awaitsHealthExport).map(\.id) == [completed.id])
        #expect(stored.records.first?.healthExportRequestedAt == completed.endedAt)
        #expect(stored.records.last?.id == local.id)
    }

    @Test @MainActor func testDeletingProgramDoesNotRewriteHistory() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = JournalStore(url: file)
        let first = try #require(store.journal.activeProgram)
        let routine = try #require(first.routines.first)
        #expect(store.start(routine, at: time))
        let draft = try #require(store.journal.activeWorkout)
        store.toggleSet(exerciseID: draft.exercises[0].id, setID: draft.exercises[0].sets[0].id, at: time)
        let finished = try #require(store.finish(at: time.addingTimeInterval(30)))
        let custom = Program(name: "Моя программа", routines: [Routine(name: "Всё тело", exercises: [ExercisePlan(name: "Подъём гантелей")])])
        #expect(store.save(custom))
        store.deleteProgram(first.id)
        let stored = try JournalFile.load(file)
        #expect(stored.records == [finished])
        #expect(stored.activeProgram == custom)
    }

    @Test func testCalendarUsesMondayAndMatchesTodayAcrossSundayBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Moscow"))
        calendar.firstWeekday = 1
        let sunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 23)))
        let monday = try #require(calendar.date(byAdding: .hour, value: 2, to: sunday))
        var journal = Journal.fresh()
        let plan = try #require(journal.activeProgram?.routines.first)
        var draft = ActiveWorkout(routine: plan, now: monday)
        draft.exercises[0].sets[0].complete = true
        journal.records = [WorkoutRecord(draft, endedAt: monday.addingTimeInterval(60))]
        #expect(journal.week(containing: sunday, calendar: calendar).map(\.count) == [0, 0, 0, 0, 0, 0, 0])
        let week = journal.week(containing: monday, calendar: calendar)
        #expect(week.map(\.weekday) == Weekday.allCases)
        #expect(week.filter(\.isToday).first?.weekday == .mon)
        #expect(week.first?.count == 1)
        #expect(journal.suggestion(on: monday, calendar: calendar)?.id != plan.id)
    }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "RitmTests-\(UUID())").appending(path: "journal.json")
    }
}

@Test @MainActor func backupRoundTripRestoresLocalGoalsAndProtectsCurrentHealthPreference() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "journal.json")
    let store = JournalStore(url: url)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var archive = Journal.fresh()
    archive.healthEnabled = true
    archive.nutritionGoals = NutritionGoals(amounts: [.fiber: 25])
    archive.sleepGoalMinutes = 450
    archive.recoveryCheckIns = [RecoveryCheckIn(date: now, feeling: .good)]
    var draft = ActiveWorkout(routine: archive.programs[0].routines[0], now: now)
    draft.restUntil = now.addingTimeInterval(60)
    archive.activeWorkout = draft

    let data = try JSONEncoder().encode(JournalBackup(createdAt: now, journal: archive))
    let decoded = try JournalBackup.decode(data)
    #expect(store.restore(decoded))
    let reread = try JournalFile.load(url)
    #expect(reread.healthEnabled == false)
    #expect(reread.activeWorkout?.restUntil == nil)
    #expect(reread.programs == archive.programs)
    #expect(reread.nutritionGoals?[.fiber] == 25)
    #expect(reread.recoveryCheckIns == archive.recoveryCheckIns)
    #expect(reread.sleepGoal == 450)

    let unsupported = try JSONEncoder().encode(JournalBackup(formatVersion: 2, journal: archive))
    #expect(throws: CocoaError.self) { try JournalBackup.decode(unsupported) }
    #expect(try JournalFile.load(url) == reread)
}
