import Foundation
import Observation
#if os(iOS)
import WidgetKit
#endif

enum JournalFile {
    static func load(_ url: URL) throws -> Journal {
        do {
            let decoded = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: url))
            guard decoded.version == 1 else { throw CocoaError(.fileReadUnknown) }
            return decoded
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .fresh()
        }
    }

    static func save(_ journal: Journal, to url: URL) throws {
        var folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #if os(iOS)
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try folder.setResourceValues(resources)
        #endif
        let data = try JSONEncoder().encode(journal)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}

struct JournalBackup: Codable {
    var formatVersion = 1
    var createdAt = Date.now
    let journal: Journal
    var healthOS: HealthOSArchive? = nil

    static func decode(_ data: Data) throws -> Self {
        let archive = try JSONDecoder().decode(Self.self, from: data)
        guard archive.formatVersion == 1, archive.journal.version == 1 else { throw CocoaError(.fileReadUnknown) }
        if let healthOS = archive.healthOS { try healthOS.validate() }
        return archive
    }
}

@MainActor @Observable final class JournalStore {
    private let url: URL
    private(set) var journal: Journal
    private(set) var isReadable = true
    var error: String?
    @ObservationIgnored var onRestChanged: ((WorkoutRest?) -> Void)?

    init(url: URL) {
        self.url = url
        do { journal = try JournalFile.load(url) }
        catch {
            journal = .fresh()
            isReadable = false
            self.error = "Не удалось открыть журнал. Исходный файл сохранён. Попробуйте открыть журнал ещё раз."
        }
    }

    func reload() {
        do {
            let previousRest = journal.activeWorkout?.rest
            journal = try JournalFile.load(url)
            isReadable = true
            error = nil
            if journal.activeWorkout?.rest != previousRest { onRestChanged?(journal.activeWorkout?.rest) }
        }
        catch { self.error = "Не удалось открыть журнал. Исходный файл сохранён." }
    }

    @discardableResult func change(_ update: (inout Journal) -> Void) -> Bool {
        guard isReadable else { return false }
        let previousRest = journal.activeWorkout?.rest
        var next = journal
        next.retainCustomExercises()
        update(&next)
        next.retainCustomExercises()
        do {
            try JournalFile.save(next, to: url)
            journal = next
            if next.activeWorkout?.rest != previousRest { onRestChanged?(next.activeWorkout?.rest) }
            publishWidgets()
            return true
        } catch {
            self.error = "Не удалось сохранить изменения. Проверьте свободное место и попробуйте ещё раз."
            return false
        }
    }

    @discardableResult func applyPreviousSet(_ previous: PreviousSet, to step: WorkoutStep) -> Bool {
        guard let draft = journal.activeWorkout,
              let exercise = draft.exercises.firstIndex(where: { $0.id == step.exerciseID }),
              let set = draft.exercises[exercise].sets.firstIndex(where: { $0.id == step.id && !$0.complete }) else { return false }
        return updateWorkout {
            $0.exercises[exercise].sets[set].value = previous.value
            $0.exercises[exercise].sets[set].weight = previous.weight
        }
    }

    @discardableResult func restore(_ backup: JournalBackup) -> Bool {
        var replacement = backup.journal
        replacement.retainCustomExercises()
        let previousRest = journal.activeWorkout?.rest
        replacement.healthEnabled = journal.healthEnabled
        replacement.activeWorkout?.restUntil = nil
        let exported = Set(journal.records.filter(\.healthExported).map(\.id))
        for index in replacement.records.indices {
            replacement.records[index].healthExportRequestedAt = nil
            if exported.contains(replacement.records[index].id) { replacement.records[index].healthExported = true }
        }
        do {
            try JournalFile.save(replacement, to: url)
            journal = replacement
            isReadable = true
            error = nil
            if previousRest != nil { onRestChanged?(nil) }
            publishWidgets()
            return true
        } catch {
            self.error = "Не удалось восстановить копию. Журнал остался на устройстве."
            return false
        }
    }

    @discardableResult func save(_ program: Program) -> Bool {
        change {
            for plan in program.routines.flatMap(\.exercises) { $0.rememberExercise(plan) }
            if let index = $0.programs.firstIndex(where: { $0.id == program.id }) { $0.programs[index] = program }
            else { $0.programs.append(program) }
            if $0.activeProgramID == nil { $0.activeProgramID = program.id }
        }
    }

    @discardableResult func saveExercise(_ plan: ExercisePlan) -> Bool {
        guard plan.isUserDefined, !plan.name.trimmed.isEmpty else { return false }
        return change { $0.rememberExercise(plan) }
    }

    func deleteProgram(_ id: UUID) {
        change {
            $0.programs.removeAll { $0.id == id }
            if $0.activeProgramID == id { $0.activeProgramID = $0.programs.first?.id }
        }
    }

    @discardableResult func start(_ routine: Routine?, at date: Date = .now) -> Bool {
        guard journal.activeWorkout == nil else { return true }
        return change { $0.activeWorkout = ActiveWorkout(routine: routine, now: date) }
    }

    @discardableResult func updateWorkout(_ update: (inout ActiveWorkout) -> Void) -> Bool {
        guard var draft = journal.activeWorkout else { return false }
        update(&draft)
        return change {
            for exercise in draft.exercises { $0.rememberExercise(exercise.plan) }
            $0.activeWorkout = draft
        }
    }

    func toggleSet(exerciseID: UUID, setID: UUID, at date: Date = .now) {
        updateWorkout { draft in
            guard let e = draft.exercises.firstIndex(where: { $0.id == exerciseID }),
                  let s = draft.exercises[e].sets.firstIndex(where: { $0.id == setID }) else { return }
            draft.exercises[e].sets[s].complete.toggle()
            let rest = draft.restAfter(setID: setID)
            if draft.exercises[e].sets[s].complete {
                draft.restUntil = rest > 0 && draft.marked < draft.total ? date.addingTimeInterval(Double(rest)) : nil
            } else {
                draft.restUntil = nil
            }
        }
    }

    func mergePulse(_ new: [PulsePoint], workoutID: UUID, now: Date = .now) {
        guard journal.healthEnabled, !new.isEmpty else { return }
        if let draft = journal.activeWorkout, draft.id == workoutID {
            let points = PulsePoint.cleaned((draft.pulse ?? []) + new, from: draft.startedAt, through: now)
            if points != draft.pulse ?? [] { updateWorkout { $0.pulse = points } }
        } else if let record = journal.records.first(where: { $0.id == workoutID }) {
            let points = PulsePoint.cleaned((record.pulse ?? []) + new, from: record.startedAt, through: record.endedAt)
            if points != record.pulse ?? [] {
                change { journal in
                    if let index = journal.records.firstIndex(where: { $0.id == workoutID }) {
                        journal.records[index].pulse = points
                    }
                }
            }
        }
    }

    func finish(at date: Date = .now) -> WorkoutRecord? {
        guard let draft = journal.activeWorkout, draft.marked > 0 else { return nil }
        var record = WorkoutRecord(draft, endedAt: date)
        if journal.healthEnabled { record.healthExportRequestedAt = record.endedAt }
        guard change({ $0.records.insert(record, at: 0); $0.activeWorkout = nil }) else { return nil }
        return record
    }

    func publishWidgets(at now: Date = .now) {
        #if os(iOS)
        guard isReadable else { return }
        let targets = WidgetTargets(nutrition: journal.nutritionGoals ?? NutritionGoals(), sleepMinutes: journal.sleepGoal)
        if targets != WidgetTargets.load(), (try? WidgetStorage.write(targets, file: WidgetTargets.file)) != nil {
            WidgetCenter.shared.reloadTimelines(ofKind: HealthWidgetSnapshot.nutritionKind)
            WidgetCenter.shared.reloadTimelines(ofKind: "RitmFiber")
            WidgetCenter.shared.reloadTimelines(ofKind: "RitmProtein")
            WidgetCenter.shared.reloadTimelines(ofKind: "RitmSleepGoal")
            for kind in RecoverySnapshot.widgetKinds { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? .distantPast
        let previous = WidgetSnapshot.load()
        let snapshot = WidgetSnapshot(activeWorkout: journal.activeWorkout?.name,
            completedSets: journal.activeWorkout?.marked ?? 0, totalSets: journal.activeWorkout?.total ?? 0,
            routines: (journal.activeProgram?.routines ?? []).map { .init(id: $0.id, title: $0.name, weekday: $0.weekday?.rawValue) },
            completions: journal.records.filter { $0.startedAt >= cutoff }.map { .init(routineID: $0.routineID, date: $0.startedAt) },
            weeklyGoal: journal.weeklyGoal)
        guard snapshot != previous else { return }
        do { try WidgetSnapshot.write(snapshot) } catch { return }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.workoutKind)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.weekKind)
        #endif
    }

    var watchSnapshot: WatchSnapshot? {
        guard let draft = journal.activeWorkout else { return nil }
        let next = draft.nextStep.map { step in
            let kind = step.set.dropStage.map { " · Дроп \($0)" } ?? ""
            let weight = step.set.weight > 0 ? " · \(step.set.weight.formatted(.number.precision(.fractionLength(0...2)))) кг" : ""
            return WatchSnapshot.NextSet(exerciseID: step.exerciseID, setID: step.id,
                                         label: "\(step.name) · \(step.set.value) \(step.unit.short)\(weight)\(kind)")
        }
        return WatchSnapshot(workoutID: draft.id, title: draft.name, kind: draft.kind.rawValue,
                             startedAt: draft.startedAt, completed: draft.marked, total: draft.total,
                             next: next, restUntil: draft.restUntil, healthEnabled: journal.healthEnabled)
    }

    func receiveWatch(_ event: WatchEvent) -> Bool {
        switch event {
        case let .mark(workoutID, exerciseID, setID):
            guard let draft = journal.activeWorkout, draft.id == workoutID,
                  let exercise = draft.exercises.first(where: { $0.id == exerciseID }),
                  let set = exercise.sets.first(where: { $0.id == setID }) else { return false }
            if !set.complete { toggleSet(exerciseID: exerciseID, setID: setID) }
            return journal.activeWorkout?.exercises.first(where: { $0.id == exerciseID })?.sets.first(where: { $0.id == setID })?.complete == true
        case let .pulse(workoutID, points):
            mergePulse(points, workoutID: workoutID)
            return true
        case let .finished(activity):
            guard activity.startedAt <= activity.endedAt, let kind = WorkoutKind(rawValue: activity.kind) else { return false }
            if journal.records.contains(where: { $0.id == activity.id }) { return true }
            var draft = ActiveWorkout(routine: Routine(name: kind.title, kind: kind), now: activity.startedAt)
            draft.id = activity.id
            if journal.healthEnabled {
                draft.pulse = PulsePoint.cleaned(activity.pulse, from: activity.startedAt, through: activity.endedAt)
            }
            var record = WorkoutRecord(draft, endedAt: activity.endedAt)
            record.fromWatch = true
            record.healthExported = true
            return change {
                $0.records.append(record)
                $0.records.sort { $0.startedAt > $1.startedAt }
            }
        }
    }

    static func live() -> JournalStore {
        let root = URL.applicationSupportDirectory.appending(path: "Ritm", directoryHint: .isDirectory)
        return JournalStore(url: root.appending(path: "journal.json"))
    }
}
