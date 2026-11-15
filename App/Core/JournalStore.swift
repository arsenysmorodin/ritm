import Foundation
import Observation

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

@MainActor @Observable final class JournalStore {
    private let url: URL
    private(set) var journal: Journal
    private(set) var isReadable = true
    var error: String?

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
        do { journal = try JournalFile.load(url); isReadable = true; error = nil }
        catch { self.error = "Не удалось открыть журнал. Исходный файл сохранён." }
    }

    @discardableResult func change(_ update: (inout Journal) -> Void) -> Bool {
        guard isReadable else { return false }
        var next = journal
        update(&next)
        do {
            try JournalFile.save(next, to: url)
            journal = next
            return true
        } catch {
            self.error = "Не удалось сохранить изменения. Проверьте свободное место и попробуйте ещё раз."
            return false
        }
    }

    @discardableResult func save(_ program: Program) -> Bool {
        change {
            if let index = $0.programs.firstIndex(where: { $0.id == program.id }) { $0.programs[index] = program }
            else { $0.programs.append(program) }
            if $0.activeProgramID == nil { $0.activeProgramID = program.id }
        }
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
        return change { $0.activeWorkout = draft }
    }

    func toggleSet(exerciseID: UUID, setID: UUID, at date: Date = .now) {
        updateWorkout { draft in
            guard let e = draft.exercises.firstIndex(where: { $0.id == exerciseID }),
                  let s = draft.exercises[e].sets.firstIndex(where: { $0.id == setID }) else { return }
            draft.exercises[e].sets[s].complete.toggle()
            let rest = draft.exercises[e].plan.rest
            if draft.exercises[e].sets[s].complete {
                draft.restUntil = rest > 0 && draft.marked < draft.total ? date.addingTimeInterval(Double(rest)) : nil
            } else {
                draft.restUntil = nil
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

    static func live() -> JournalStore {
        let root = URL.applicationSupportDirectory.appending(path: "Ritm", directoryHint: .isDirectory)
        return JournalStore(url: root.appending(path: "journal.json"))
    }
}
