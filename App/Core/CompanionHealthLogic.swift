import Foundation

extension HealthOSStore {
    @discardableResult func receiveWatchHealth(_ action: WatchHealthAction, now: Date = .now) -> Bool {
        reload()
        guard isReadable, action.isValid(at: now) else { return false }
        // A replay must never overwrite an edit or resurrect a deleted entry.
        if let existing = archive.events.first(where: { $0.id == action.id }) { return existing.source == "Apple Watch" }
        let zone = TimeZone(identifier: action.timezone)!
        var event = HealthEvent(id: action.id, kind: action.kind == .water ? .water : .checkIn,
            date: action.date, timezone: action.timezone, offsetSeconds: zone.secondsFromGMT(for: action.date),
            updatedAt: action.date, title: action.kind == .water ? "Вода" : "Самочувствие",
            amount: action.amount.map(Double.init), unit: action.kind == .water ? "мл" : "", source: "Apple Watch",
            ratings: action.ratings)
        event.needsHealthSync = action.kind == .water
        return log(event)
    }
}

enum CompanionHealthLogic {
    static func snapshot(archive: HealthOSArchive, readable: Bool, healthEnabled: Bool,
                         recovery: RecoverySnapshot?, heart: HealthWidgetSnapshot?, activity: ActivityWidgetSnapshot?,
                         now: Date = .now, calendar: Calendar = .current) -> WatchHealthSnapshot {
        var result = WatchHealthSnapshot(generatedAt: now, day: calendar.startOfDay(for: now),
            readable: readable, healthEnabled: healthEnabled, waterML: HealthOSLogic.total(.water, events: archive.events, day: now, calendar: calendar),
            waterGoal: archive.settings.waterGoal, waterPortions: archive.settings.waterPortions)
        if let check = HealthOSLogic.events(archive.events, on: now, kind: .checkIn, calendar: calendar).first {
            result.checkIn = WatchHealthAction(id: check.id, kind: .checkIn, date: check.date, timezone: check.timezone, ratings: check.ratings)
        }
        var nextSlot: Date?
        for supplement in archive.supplements where !supplement.archived {
            for slot in supplement.slots(on: now, calendar: calendar) {
                result.supplementsPlanned += 1
                let events = archive.events.filter { !$0.deleted && $0.linkedID == supplement.id && $0.scheduledAt == slot }
                if events.contains(where: { !$0.skipped }) { result.supplementsTaken += 1 }
                if slot > now, events.isEmpty, nextSlot.map({ slot < $0 }) ?? true {
                    nextSlot = slot; result.nextSupplement = supplement.name
                }
            }
        }
        guard healthEnabled else { return result }
        if let night = recovery?.recentNight(at: now, calendar: calendar), let sleep = night.sleep {
            result.metrics.append(.init(kind: .sleep, value: sleep.sleptSeconds / 60, measuredAt: sleep.end))
            for (metric, kind) in [(RecoveryMetric.hrv, WatchHealthMetricKind.hrv), (.restingPulse, .restingPulse)] {
                if let reading = night.readings[metric] {
                    let range = recovery?.range(for: metric, on: night, calendar: calendar)
                    result.metrics.append(.init(kind: kind, value: reading.value, measuredAt: reading.date,
                        rangeLower: range?.lower, rangeUpper: range?.upper, historyDays: range?.count))
                }
            }
        }
        if let pulse = heart?.pulse.recent(at: now) {
            result.metrics.append(.init(kind: .pulse, value: pulse.value, measuredAt: pulse.date))
        }
        if let day = activity?.day(at: now, calendar: calendar) {
            if let steps = day.steps { result.metrics.append(.init(kind: .steps, value: Double(steps), measuredAt: day.date)) }
            if let energy = day.activeEnergy { result.metrics.append(.init(kind: .activeEnergy, value: Double(energy), measuredAt: day.date)) }
        }
        for (nutrient, kind) in [(Nutrient.energy, WatchHealthMetricKind.calories), (.protein, .protein), (.fiber, .fiber)] {
            if let value = heart?.nutrient(nutrient, at: now) { result.metrics.append(.init(kind: kind, value: value, measuredAt: heart!.day)) }
        }
        return result
    }
}
