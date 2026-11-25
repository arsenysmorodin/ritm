import Foundation
import Testing
@testable import RitmCore

private func companionCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
    return calendar
}

private func companionNow(hour: Int = 12) -> Date {
    companionCalendar().date(from: DateComponents(year: 2026, month: 11, day: 25, hour: hour))!
}

private func companionRecovery(days: Int = 21, changed: Bool = true, source: String = "watch") -> RecoverySnapshot {
    let calendar = companionCalendar(), today = calendar.startOfDay(for: companionNow())
    return RecoverySnapshot(days: (0..<days).map { index in
        let day = calendar.date(byAdding: .day, value: index - days + 1, to: today)!
        let end = day.addingTimeInterval(7 * 3600), current = index == days - 1
        let sleep = SleepNight(day: day, sourceID: "watch", sourceName: "Watch", spans: [
            SleepSpan(start: day.addingTimeInterval(-3600), end: end, phase: .core)
        ], inBedSeconds: nil)
        return RecoveryDay(date: day, sleep: sleep, readings: [
            .hrv: .init(date: end, value: current && changed ? 20 : 40 + Double(index % 3), sourceID: current ? source : "watch", sourceName: "Watch", count: 4),
            .sleepingPulse: .init(date: end, value: current && changed ? 90 : 55 + Double(index % 3), sourceID: current ? source : "watch", sourceName: "Watch", count: 30)
        ])
    })
}

@Test func existingHealthSettingsDecodeWithoutProactiveOptions() throws {
    let data = Data(#"{"waterGoal":2000,"waterPortions":[150,250,500],"waterReminderTimes":[],"supplementReminders":false,"writeIntakeToHealth":false}"#.utf8)
    let settings = try JSONDecoder().decode(HealthOSSettings.self, from: data)
    #expect(settings.waterGoal == 2000)
    #expect(!settings.proactive.enabled)
    #expect(settings.proactive.isValid)
}

@Test @MainActor func watchHealthReplayPreservesPhoneEditsAndDeletedEntries() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "ritm-companion-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = HealthOSStore(url: folder.appending(path: "health.sqlite"))
    let action = WatchHealthAction(kind: .water, date: .now.addingTimeInterval(-10), amount: 250)
    #expect(store.receiveWatchHealth(action))
    #expect(store.receiveWatchHealth(action))
    #expect(store.events.count == 1)
    var edited = try #require(store.events.first)
    edited.amount = 375
    #expect(store.log(edited))
    #expect(store.receiveWatchHealth(action))
    #expect(store.events.first?.amount == 375)
    store.delete(edited)
    #expect(store.receiveWatchHealth(action))
    #expect(store.events.isEmpty)
    #expect(store.archive.events.count == 1)
}

@Test @MainActor func watchCheckInUsesRecordedDateAndFeedsExistingDailyAnalysis() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "ritm-checkin-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = HealthOSStore(url: folder.appending(path: "health.sqlite"))
    let date = Date.now.addingTimeInterval(-86400)
    let action = WatchHealthAction(kind: .checkIn, date: date, timezone: "Europe/Moscow", ratings: ["energy": 4, "stress": 2])
    #expect(store.receiveWatchHealth(action))
    #expect(store.events.first?.date == date)
    #expect(store.days.first?.values[.energy] == 4)
    #expect(store.days.first?.values[.stress] == 2)
    #expect(store.events.first?.ratings["sleepiness"] == nil)
}

@Test func watchActionsRejectInvalidOrInventedValues() {
    let now = Date.now
    #expect(!WatchHealthAction(kind: .water, amount: 0).isValid(at: now))
    #expect(!WatchHealthAction(kind: .water, amount: 5001).isValid(at: now))
    #expect(!WatchHealthAction(kind: .checkIn, ratings: [:]).isValid(at: now))
    #expect(!WatchHealthAction(kind: .checkIn, ratings: ["energy": 6]).isValid(at: now))
    #expect(!WatchHealthAction(kind: .checkIn, ratings: ["unknown": 3]).isValid(at: now))
    #expect(!WatchHealthAction(kind: .water, date: now.addingTimeInterval(120), amount: 250).isValid(at: now))
}

@Test func watchOutboxRequiresAnAcceptedReceiptBeforeDroppingAnEntry() throws {
    let action = WatchHealthAction(kind: .checkIn, ratings: ["energy": 4])
    var outbox = WatchHealthOutbox()
    outbox.append(action); outbox.append(action)
    outbox = try JSONDecoder().decode(WatchHealthOutbox.self, from: JSONEncoder().encode(outbox))
    #expect(outbox.actions == [action])
    outbox.acknowledge(.init(id: action.id, accepted: false))
    #expect(outbox.actions.count == 1)
    outbox.acknowledge(.init(id: action.id, accepted: true))
    outbox.acknowledge(.init(id: action.id, accepted: true))
    #expect(outbox.actions.isEmpty)
}

@Test func healthContextCanEndAWorkoutWithoutDroppingTheDayOverview() throws {
    let snapshot = WatchHealthSnapshot(day: companionCalendar().startOfDay(for: companionNow()), waterML: 750)
    let data = try JSONEncoder().encode(WatchAppContext(workout: nil, health: snapshot))
    let context = try JSONDecoder().decode(WatchAppContext.self, from: data)
    #expect(context.workout == nil)
    #expect(context.health == snapshot)
    #expect(!snapshot.isToday(at: companionNow().addingTimeInterval(86400), calendar: companionCalendar()))
}

@Test func watchOverviewDoesNotExposeCachedHealthAfterDisconnecting() {
    let snapshot = CompanionHealthLogic.snapshot(archive: HealthOSArchive(), readable: true, healthEnabled: false,
        recovery: companionRecovery(), heart: nil, activity: nil, now: companionNow(), calendar: companionCalendar())
    #expect(snapshot.metrics.isEmpty)
    #expect(!snapshot.healthEnabled)
    #expect(snapshot.metric(.pulse) == nil)
}

@Test func eveningReminderDisappearsAfterACheckInAndQuietHoursMoveScheduledPrompts() {
    let now = companionNow(hour: 6), calendar = companionCalendar()
    var settings = ProactiveNotificationSettings()
    settings.morning = true; settings.morningMinute = 7 * 60; settings.checkIn = true
    let plans = ProactiveNotificationPlanner.scheduled(settings: settings, events: [], now: now, calendar: calendar)
    #expect(plans.first(where: { $0.kind == .morning })?.repeatMinute == 8 * 60)
    #expect(plans.filter { $0.kind == .checkIn }.count == 7)
    let entry = HealthEvent(kind: .checkIn, date: now, ratings: ["energy": 4])
    let updated = ProactiveNotificationPlanner.scheduled(settings: settings, events: [entry], now: now, calendar: calendar)
    #expect(updated.filter { $0.kind == .checkIn }.count == 6)
    #expect(updated.allSatisfy { !settings.isQuiet($0.date, calendar: calendar) })
}

@Test func changeAlertsNeedTwoDeviationsAndEnoughHistoryFromTheSameSource() throws {
    var settings = ProactiveNotificationSettings(); settings.healthChanges = true
    let now = companionNow(), calendar = companionCalendar()
    let alert = try #require(ProactiveNotificationPlanner.healthChange(settings: settings, snapshot: companionRecovery(), now: now, calendar: calendar))
    #expect(alert.route == "recovery")
    #expect(ProactiveNotificationPlanner.healthChange(settings: settings, snapshot: companionRecovery(days: 10), now: now, calendar: calendar) == nil)
    #expect(ProactiveNotificationPlanner.healthChange(settings: settings, snapshot: companionRecovery(source: "new-watch"), now: now, calendar: calendar) == nil)
    #expect(ProactiveNotificationPlanner.healthChange(settings: settings, snapshot: companionRecovery(changed: false), now: now, calendar: calendar) == nil)
    #expect(ProactiveNotificationPlanner.healthChange(settings: settings, snapshot: companionRecovery(), now: companionNow(hour: 23), calendar: calendar) == nil)
    #expect(!ProactiveNotificationPlanner.mayDeliver(alert, receipts: [alert.id: now], now: now.addingTimeInterval(60)))
    #expect(!ProactiveNotificationPlanner.mayDeliver(alert, receipts: ["ritm.health.proactive.change.previous": now.addingTimeInterval(-3600)], now: now))
}

@Test func quietHoursMoveLateCheckInIntoTheFollowingMorning() throws {
    var settings = ProactiveNotificationSettings()
    settings.checkIn = true; settings.checkInMinute = 23 * 60
    let calendar = companionCalendar(), now = companionNow(hour: 12)
    let first = try #require(ProactiveNotificationPlanner.scheduled(settings: settings, events: [], now: now, calendar: calendar).first)
    #expect(calendar.component(.hour, from: first.date) == 8)
    let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: now))
    #expect(calendar.isDate(first.date, inSameDayAs: tomorrow))
    #expect(!settings.isQuiet(first.date, calendar: calendar))
    let check = HealthEvent(kind: .checkIn, date: now, title: "Самочувствие", ratings: ["energy": 4])
    let afterCheck = ProactiveNotificationPlanner.scheduled(settings: settings, events: [check], now: now, calendar: calendar)
    #expect(!afterCheck.contains { $0.id == first.id })
}
