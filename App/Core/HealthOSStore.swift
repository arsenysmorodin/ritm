import Foundation
import Observation
#if os(iOS)
import WidgetKit
#endif

@MainActor @Observable final class HealthOSStore {
    private let database: HealthDatabase?
    private(set) var archive = HealthOSArchive()
    private(set) var isReadable = false
    var error: String?
    var isImporting = false
    var importMessage: String?
    @ObservationIgnored var onChange: (() -> Void)?
    static let widgetKinds = ["RitmWater", "RitmSupplements", "RitmCaffeine", "RitmDayTimeline",
        "RitmDailyResource", "RitmDaylight", "RitmFiber", "RitmProtein", "RitmWaterWeek",
        "RitmExperiment", "RitmSleepGoal", "RitmLastMeal"]

    init(url: URL? = nil) {
        do { database = try HealthDatabase(url: try url ?? HealthDatabase.sharedURL()) }
        catch { database = nil; self.error = "Не удалось открыть Health OS. \(error.localizedDescription)" }
        reload()
    }

    var settings: HealthOSSettings { archive.settings }
    var events: [HealthEvent] { archive.events.filter { !$0.deleted } }
    var days: [DailyHealth] { HealthOSLogic.dailyValues(archive.days, events: archive.events) }
    var supplements: [Supplement] { archive.supplements.filter { !$0.archived } }
    var experiments: [HealthExperiment] { archive.experiments.sorted { $0.startsAt > $1.startsAt } }

    func reload() {
        guard let database else { return }
        do { archive = try database.archive(); isReadable = true }
        catch { isReadable = false; self.error = "Не удалось прочитать Health OS. Исходная база сохранена. \(error.localizedDescription)" }
    }

    func total(_ kind: HealthEventKind, on day: Date = .now) -> Double {
        HealthOSLogic.total(kind, events: archive.events, day: day)
    }

    @discardableResult func log(_ event: HealthEvent) -> Bool {
        guard event.date <= Date.now.addingTimeInterval(60), event.amount.map({ $0.isFinite && $0 > 0 }) ?? true else {
            error = "Укажите положительное количество и время не позднее текущего."; return false
        }
        if event.kind == .water && (event.amount ?? 0) > 10000 { error = "Проверьте объём воды: максимум 10 000 мл за одну запись."; return false }
        if event.kind == .caffeine && (event.amount ?? 0) > 2000 { error = "Проверьте количество кофеина: максимум 2000 мг за запись."; return false }
        return mutate { try $0.save(event) }
    }

    @discardableResult func addWater(_ ml: Int) -> Bool { log(.water(Double(ml))) }

    func delete(_ event: HealthEvent) {
        guard event.isLocal else { error = "Эта запись пришла из «Здоровья». Измените её в исходном приложении."; return }
        var removed = event; removed.deleted = true; removed.updatedAt = .now
        removed.needsHealthSync = event.kind == .water || event.kind == .caffeine
        _ = mutate { try $0.save(removed) }
    }

    @discardableResult func take(_ supplement: Supplement, slot: Date, skipped: Bool = false, at date: Date = .now) -> Bool {
        mutate { _ = try $0.take(supplement, at: slot, skipped: skipped, now: date) }
    }

    @discardableResult func saveSupplement(_ supplement: Supplement) -> Bool {
        guard !supplement.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              supplement.servings.isFinite, supplement.servings > 0, !supplement.times.isEmpty,
              supplement.times.allSatisfy({ (0..<1440).contains($0) }), !supplement.weekdays.isEmpty,
              supplement.ingredients.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.amount.isFinite && $0.amount > 0 }),
              supplement.endsAt.map({ $0 >= supplement.startsAt }) ?? true else {
            error = "Проверьте название, состав, порцию и даты курса."; return false
        }
        var next = archive
        if let index = next.supplements.firstIndex(where: { $0.id == supplement.id }) { next.supplements[index] = supplement }
        else { next.supplements.append(supplement) }
        return mutate { try $0.saveConfiguration(next) }
    }

    func archiveSupplement(_ supplement: Supplement) {
        var copy = supplement; copy.archived = true; _ = saveSupplement(copy)
    }

    @discardableResult func saveSettings(_ settings: HealthOSSettings) -> Bool {
        guard (100...10000).contains(settings.waterGoal), !settings.waterPortions.isEmpty,
              settings.waterPortions.allSatisfy({ (10...5000).contains($0) }),
              settings.waterReminderTimes.allSatisfy({ (0..<1440).contains($0) }) else {
            error = "Проверьте цель, порции воды и время напоминаний."; return false
        }
        var next = archive; next.settings = settings
        return mutate { try $0.saveConfiguration(next) }
    }

    @discardableResult func saveExperiment(_ experiment: HealthExperiment) -> Bool {
        guard !experiment.title.trimmingCharacters(in: .whitespaces).isEmpty,
              !experiment.rule.trimmingCharacters(in: .whitespaces).isEmpty,
              !experiment.conditionA.trimmingCharacters(in: .whitespaces).isEmpty,
              !experiment.conditionB.trimmingCharacters(in: .whitespaces).isEmpty,
              (2...28).contains(experiment.blockDays), (0..<experiment.blockDays).contains(experiment.adaptationDays),
              experiment.blocks.count == 4, experiment.blocks.filter({ $0 }).count == 2 else {
            error = "Укажите условия, правило соблюдения и допустимую длительность блоков."; return false
        }
        var next = archive
        if let index = next.experiments.firstIndex(where: { $0.id == experiment.id }) {
            var original = next.experiments[index]
            if experiment.finished && !original.finished { original.finished = true; original.finishedAt = .now }
            next.experiments[index] = original // Prespecified plans remain immutable.
        } else { next.experiments.append(experiment) }
        return mutate { try $0.saveConfiguration(next) }
    }

    func markExperiment(_ experiment: HealthExperiment, on day: Date = .now, adhered: Bool) {
        guard !experiment.finished, experiment.assignment(on: day) != nil else { return }
        let existing = events.first { $0.kind == .experiment && $0.linkedID == experiment.id && Calendar.current.isDate($0.date, inSameDayAs: day) }
        var event = existing ?? HealthEvent(kind: .experiment, date: day, title: experiment.title, linkedID: experiment.id)
        event.ratings["adhered"] = adhered ? 1 : 0; event.updatedAt = .now
        _ = log(event)
    }

    func importHealth(from start: Date, to end: Date, events: [HealthEvent], days: [DailyHealth]) throws {
        guard let database, isReadable else { throw HealthDatabase.DatabaseError(message: "Локальная база недоступна.") }
        try database.importWindow(from: start, to: end, events: events, days: days)
        reload()
        var updated = settings; updated.importedThrough = end
        _ = saveSettings(updated)
        reloadWidgets()
    }

    func markSynced(_ event: HealthEvent) throws {
        guard let database else { return }
        // A newer edit must remain queued if it happened while HealthKit was saving.
        let latest = try database.archive().events.first { $0.id == event.id }
        guard var latest, latest.updatedAt == event.updatedAt else { return }
        latest.needsHealthSync = false
        try database.save(latest); reload()
    }

    func clearImported() {
        _ = mutate { try $0.clearImported() }
    }

    @discardableResult func restore(_ archive: HealthOSArchive) -> Bool {
        mutate { try $0.restore(archive) }
    }

    func exportArchive() throws -> HealthOSArchive {
        guard let database, isReadable else { throw HealthDatabase.DatabaseError(message: "База Health OS недоступна.") }
        return try database.archive()
    }

    private func mutate(_ action: (HealthDatabase) throws -> Void) -> Bool {
        guard let database, isReadable else { return false }
        do { try action(database); error = nil; reload(); reloadWidgets(); onChange?(); return true }
        catch { self.error = "Не удалось сохранить Health OS. \(error.localizedDescription)"; return false }
    }
    private func reloadWidgets() {
        #if os(iOS)
        for kind in Self.widgetKinds { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
        #endif
    }
}
