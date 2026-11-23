import Foundation
import Testing
@testable import RitmCore

private func healthTestURL() -> URL { FileManager.default.temporaryDirectory.appending(path: "ritm-health-test-\(UUID())/health.sqlite") }
private func healthCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!; return calendar
}
private func healthDate(_ day: Int, hour: Int = 12) -> Date {
    healthCalendar().date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
}

@Test func editableQuantitiesAcceptCommaAndBlankWhileEditingWithoutInventingAValue() {
    #expect(HealthQuantityInput.parse("375") == 375)
    #expect(HealthQuantityInput.parse("1 250,5") == 1250.5)
    #expect(HealthQuantityInput.parse("") == nil)
    #expect(HealthQuantityInput.parse("nan") == nil)
    #expect(HealthQuantityInput.parse("1,2.3") == nil)
    #expect(HealthQuantityInput.parse(HealthQuantityInput.editingString(5.678)) == 5.678)
}

@Test func healthDatabaseSharesCommittedWaterAndRemovesOnlyImportedSamples() throws {
    let url = healthTestURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let app = try HealthDatabase(url: url), widget = try HealthDatabase(url: url)
    let water = HealthEvent.water(250, at: healthDate(10))
    try app.save(water)
    var imported = HealthEvent.water(300, at: healthDate(10)); imported.externalID = "sample-water"; imported.source = "Здоровье"
    try app.importWindow(from: healthDate(10, hour: 0), to: healthDate(11, hour: 0), events: [imported], days: [])
    #expect(HealthOSLogic.total(.water, events: try widget.archive().events, day: healthDate(10), calendar: healthCalendar()) == 550)
    // Import is repeatable; a deleted HealthKit sample disappears without deleting local water.
    try app.importWindow(from: healthDate(10, hour: 0), to: healthDate(11, hour: 0), events: [imported], days: [])
    #expect(try app.archive().events.count == 2)
    try app.importWindow(from: healthDate(10, hour: 0), to: healthDate(11, hour: 0), events: [], days: [])
    #expect(try widget.archive().events == [water])
}

@Test func supplementSlotIsIdempotentAcrossConnectionsAndKeepsHistoricalComposition() async throws {
    let url = healthTestURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let app = try HealthDatabase(url: url), widget = try HealthDatabase(url: url)
    var product = Supplement(name: "Магний", ingredients: [.init(name: "Магний", amount: 100)], servings: 2)
    let original = product, slot = healthDate(10, hour: 9)
    async let first = Task.detached { try app.take(original, at: slot, now: slot) }.value
    async let second = Task.detached { try widget.take(original, at: slot, now: slot) }.value
    let results = try await [first, second]
    #expect(results.filter { $0 }.count == 1)
    product.ingredients[0].amount = 999
    var archive = try app.archive(); archive.supplements = [product]; try app.saveConfiguration(archive)
    let events = try widget.archive().events
    #expect(events.count == 1)
    let totals = HealthOSLogic.ingredientTotals(events, on: slot, calendar: healthCalendar())
    #expect(totals.first?.amount == 200)
}

@Test func supplementTotalsExcludeSkippedAndDoNotMixUnits() {
    let date = healthDate(12)
    let events = [
        HealthEvent(kind: .supplement, date: date, amount: 2, ingredients: [.init(name: " Магний ", amount: 100)]),
        HealthEvent(kind: .supplement, date: date, amount: 1, ingredients: [.init(name: "магний", amount: 50)]),
        HealthEvent(kind: .supplement, date: date, amount: 1, ingredients: [.init(name: "магний", amount: 2, unit: .g)]),
        HealthEvent(kind: .supplement, date: date, amount: 10, skipped: true, ingredients: [.init(name: "магний", amount: 100)])
    ]
    let totals = HealthOSLogic.ingredientTotals(events, on: date, calendar: healthCalendar())
    #expect(totals.count == 2)
    #expect(totals.first(where: { $0.unit == .mg })?.amount == 250)
    #expect(totals.first(where: { $0.unit == .g })?.amount == 2)
}

@Test func unloggedHabitsAreMissingAndSleepIsPairedWithThePrecedingDay() {
    let calendar = healthCalendar()
    let days = [DailyHealth(date: healthDate(11, hour: 0), values: [.sleepMinutes: 400], sources: [.sleepMinutes: "watch"], sleepStart: healthDate(10, hour: 23)),
                DailyHealth(date: healthDate(12, hour: 0), values: [.sleepMinutes: 500], sources: [.sleepMinutes: "watch"])]
    let events = [HealthEvent(kind: .caffeine, date: healthDate(10, hour: 17), amount: 80)]
    let rows = HealthAnalytics.observations(exposure: .lateCaffeine, outcome: .sleepMinutes, days: days, events: events, workouts: [], calendar: calendar)
    #expect(rows.count == 1)
    #expect(rows[0].date == healthDate(11, hour: 0))
    #expect(rows[0].value == 400 && rows[0].exposed)
    #expect(HealthOSLogic.dailyValues(days, events: [], calendar: calendar).allSatisfy { $0.values[.water] == nil })
}

@Test func comparisonExcludesSourceChangesAndIncompleteToday() {
    let days = [DailyHealth(date: healthDate(8, hour: 0), values: [.hrv: 30], sources: [.hrv: "watch1"]),
                DailyHealth(date: healthDate(9, hour: 0), values: [.hrv: 40], sources: [.hrv: "watch1"]),
                DailyHealth(date: healthDate(10, hour: 0), values: [.hrv: 90], sources: [.hrv: "watch2"]),
                DailyHealth(date: healthDate(11, hour: 0), values: [.hrv: 999], sources: [.hrv: "watch1"])]
    let result = HealthAnalytics.comparePeriods(metric: .hrv, days: days, length: 2, now: healthDate(11), calendar: healthCalendar())
    #expect(result.excludedSources == 1)
    #expect(result.a == [30])
    #expect(result.b == [40])
    #expect(result.delta == 10)
    #expect(result.interval == nil)
}

@Test func lateNightFoodAndCaffeineBelongToTheUpcomingSleepRatherThanCalendarMidnight() {
    let calendar = healthCalendar()
    let day = DailyHealth(date: healthDate(11, hour: 0), values: [.sleepMinutes: 420], sources: [.sleepMinutes: "watch"], sleepStart: healthDate(11, hour: 2))
    let events = [HealthEvent(kind: .meal, date: healthDate(11, hour: 1)),
                  HealthEvent(kind: .caffeine, date: healthDate(11, hour: 1), amount: 80)]
    for exposure in [HealthExposure.lateMeal, .lateCaffeine] {
        let rows = HealthAnalytics.observations(exposure: exposure, outcome: .sleepMinutes, days: [day], events: events, workouts: [], calendar: calendar)
        #expect(rows.count == 1)
        #expect(rows.first?.exposed == true)
    }
}

@Test func supplementExposureRequiresAnExplicitDoseOrSkipForTheChosenProduct() {
    let calendar = healthCalendar(), product = UUID(), otherProduct = UUID()
    let days = (11...13).map { DailyHealth(date: healthDate($0, hour: 0), values: [.hrv: 40], sources: [.hrv: "watch"]) }
    let events = [HealthEvent(kind: .supplement, date: healthDate(10), linkedID: product, skipped: true),
                  HealthEvent(kind: .supplement, date: healthDate(11), linkedID: otherProduct),
                  HealthEvent(kind: .supplement, date: healthDate(12), linkedID: product)]
    let rows = HealthAnalytics.observations(exposure: .supplement, outcome: .hrv, days: days, events: events, workouts: [], supplementID: product, calendar: calendar)
    #expect(rows.count == 2)
    #expect(rows.map(\.exposed) == [false, true])
}

@Test func recordedZeroCaffeineIsKnownAbsenceRatherThanExposure() {
    let day = DailyHealth(date: healthDate(11, hour: 0), values: [.sleepMinutes: 420], sources: [.sleepMinutes: "watch"], sleepStart: healthDate(11, hour: 2))
    let events = [HealthEvent(kind: .caffeine, date: healthDate(11, hour: 1), amount: 0)]
    let rows = HealthAnalytics.observations(exposure: .lateCaffeine, outcome: .sleepMinutes, days: [day], events: events, workouts: [], calendar: healthCalendar())
    #expect(rows.count == 1 && rows[0].exposed == false)
}

@Test func experimentKeepsAssignedGroupsRegardlessOfAdherenceAndExcludesAdaptation() {
    let calendar = healthCalendar()
    let experiment = HealthExperiment(title: "Экран", startsAt: healthDate(1, hour: 0), blockDays: 2,
                                      blocks: [false, true, false, true], adaptationDays: 1, rule: "Без экрана")
    let days = (1...8).map { DailyHealth(date: healthDate($0 + 1, hour: 0), values: [.sleepMinutes: Double($0 * 10)], sources: [.sleepMinutes: "watch"]) }
    let events = [HealthEvent(kind: .experiment, date: healthDate(2), linkedID: experiment.id, ratings: ["adhered": 0]),
                  HealthEvent(kind: .experiment, date: healthDate(4), linkedID: experiment.id, ratings: ["adhered": 1])]
    let report = HealthAnalytics.report(experiment, days: days, events: events, now: healthDate(10), calendar: calendar)
    #expect(report.expectedDays == 4 && report.adaptationDays == 4)
    #expect(report.recordedAdherence == 2 && report.adheredDays == 1)
    #expect(report.comparison.a == [20, 60])
    #expect(report.comparison.b == [40, 80])
    #expect(report.comparison.interval == nil)
}

@Test @MainActor func healthBackupRestoresEventsWithoutGrantingWritesOrReExporting() throws {
    let url = healthTestURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = HealthOSStore(url: url)
    #expect(store.addWater(250))
    var archive = try store.exportArchive(); archive.settings.writeIntakeToHealth = true
    let backup = JournalBackup(journal: .fresh(), healthOS: archive)
    let decoded = try JournalBackup.decode(JSONEncoder().encode(backup))
    #expect(store.restore(try #require(decoded.healthOS)))
    #expect(!store.settings.writeIntakeToHealth)
    #expect(store.events.count == 1 && !store.events[0].needsHealthSync)
    var invalid = archive; invalid.experiments = [HealthExperiment(blockDays: 0)]
    #expect(throws: (any Error).self) { try invalid.validate() }
    #expect(store.events.count == 1)
}

@Test @MainActor func staleHealthSyncCannotClearANewerEdit() throws {
    let url = healthTestURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = HealthOSStore(url: url)
    let event = HealthEvent.water(250)
    #expect(store.log(event))
    var edited = event; edited.amount = 500; edited.updatedAt = event.updatedAt.addingTimeInterval(1)
    #expect(store.log(edited))
    try store.markSynced(event)
    #expect(store.events.first?.amount == 500 && store.events.first?.needsHealthSync == true)
    store.delete(edited)
    #expect(store.events.isEmpty)
    #expect(store.archive.events.first?.needsHealthSync == true)
}

@Test @MainActor func experimentPlanCannotChangeAfterCreation() throws {
    let url = healthTestURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = HealthOSStore(url: url)
    let plan = HealthExperiment(title: "Свет", rule: "30 минут прогулки")
    #expect(store.saveExperiment(plan))
    var changed = plan; changed.outcome = .hrv; changed.blocks.reverse(); changed.finished = true
    #expect(store.saveExperiment(changed))
    #expect(store.experiments[0].outcome == plan.outcome)
    #expect(store.experiments[0].blocks == plan.blocks)
    #expect(store.experiments[0].finished)
    #expect(store.experiments[0].finishedAt != nil)
}

@Test func stoppedExperimentNeverAddsOutcomesFromAfterItsActualStop() {
    let experiment = HealthExperiment(title: "Экран", startsAt: healthDate(1, hour: 0), blockDays: 2,
        adaptationDays: 0, rule: "Без экрана", finished: true, finishedAt: healthDate(4))
    let days = (1...10).map { DailyHealth(date: healthDate($0, hour: 0), values: [.sleepMinutes: 480], sources: [.sleepMinutes: "watch"]) }
    let report = HealthAnalytics.report(experiment, days: days, events: [], now: healthDate(15), calendar: healthCalendar())
    #expect(report.expectedDays == 3)
    #expect(report.comparison.a.count + report.comparison.b.count == 3)
}
