import Foundation
import Observation
#if os(iOS) && RITM_HEALTHKIT
import HealthKit
#endif

@MainActor @Observable final class HealthOSBridge {
    private(set) var busy = false
    var issue: String?
    private var generation = UUID()
    #if os(iOS) && RITM_HEALTHKIT
    private let health = HKHealthStore()
    private let recovery = RecoveryReader()
    private static let water = HKQuantityType(.dietaryWater)
    private static let caffeine = HKQuantityType(.dietaryCaffeine)
    private static let energy = HKQuantityType(.dietaryEnergyConsumed)
    private static let syncKey = "ritm.intake.id"
    private static let dailyTypes: [HealthMeasure: (HKQuantityType, HKUnit)] = [
        .steps: (HKQuantityType(.stepCount), .count()), .activeEnergy: (HKQuantityType(.activeEnergyBurned), .kilocalorie()),
        .daylightMinutes: (HKQuantityType(.timeInDaylight), .minute()), .fiber: (HKQuantityType(.dietaryFiber), .gram()),
        .protein: (HKQuantityType(.dietaryProtein), .gram()), .calories: (energy, .kilocalorie())
    ]
    static var readTypes: Set<HKObjectType> {
        Set<HKObjectType>([water, caffeine, energy, HKQuantityType(.bodyMass)] + dailyTypes.values.map(\.0))
    }

    func authorize(_ journal: JournalStore, daily: HealthOSStore, write: Bool = false) async {
        guard !busy, HKHealthStore.isHealthDataAvailable() else { return }
        busy = true; issue = nil
        do {
            let writes: Set<HKSampleType> = write ? [Self.water, Self.caffeine] : []
            try await health.requestAuthorization(toShare: writes, read: Self.readTypes)
            if write {
                let allowed = health.authorizationStatus(for: Self.water) == .sharingAuthorized || health.authorizationStatus(for: Self.caffeine) == .sharingAuthorized
                var settings = daily.settings; settings.writeIntakeToHealth = allowed
                _ = daily.saveSettings(settings)
                if !allowed { issue = "Запись не разрешена. Локальный журнал продолжает работать." }
            }
        } catch { issue = "Не удалось запросить разрешения Apple «Здоровья»." }
        busy = false
        await refresh(journal, daily: daily, force: true)
    }

    func refresh(_ journal: JournalStore, daily: HealthOSStore, force: Bool = false, fullHistory: Bool = false) async {
        guard !busy, journal.journal.healthEnabled, daily.isReadable, HKHealthStore.isHealthDataAvailable() else { return }
        daily.reload()
        if !force, !fullHistory, let updated = daily.settings.importedThrough, Date.now.timeIntervalSince(updated) < 15 * 60 {
            await syncIntake(daily); return
        }
        busy = true; daily.isImporting = true; issue = nil
        let request = generation
        defer { busy = false; daily.isImporting = false }
        do {
            try await exportPending(daily)
            let now = Date.now, calendar = Calendar.current
            let lookback = fullHistory || daily.settings.importedThrough == nil ? 365 : 35
            let start = calendar.date(byAdding: .day, value: -lookback, to: calendar.startOfDay(for: now)) ?? now
            let window = HKQuery.predicateForSamples(withStart: start, end: now, options: [.strictStartDate, .strictEndDate])
            async let sleep = recovery.snapshot(now: now, historyDays: lookback)
            let quantities = [Self.water, Self.caffeine, Self.energy, HKQuantityType(.bodyMass)]
            let localIDs = Set(daily.archive.events.filter(\.isLocal).map(\.id))
            let samples = try await HKSampleQueryDescriptor(predicates: quantities.map { .quantitySample(type: $0, predicate: window) }, sortDescriptors: []).result(for: health)
            var events: [HealthEvent] = []
            var days: [Date: DailyHealth] = [:]
            for sample in samples {
                if sample.quantityType == HKQuantityType(.bodyMass) {
                    let date = calendar.startOfDay(for: sample.startDate)
                    var day = days[date] ?? DailyHealth(date: date)
                    // Sorted below to keep the latest weight in each local day.
                    if let previous = day.sleepEnd, previous > sample.startDate { continue }
                    day.values[.weight] = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                    day.sources[.weight] = Self.source(sample); day.counts[.weight] = 1
                    day.sleepEnd = sample.startDate; days[date] = day
                    continue
                }
                // Own local events are canonical and already included in the total.
                if let key = sample.metadata?[Self.syncKey] as? String, let id = UUID(uuidString: key), localIDs.contains(id) { continue }
                let kind: HealthEventKind = sample.quantityType == Self.water ? .water : sample.quantityType == Self.caffeine ? .caffeine : .meal
                let unit: HKUnit = kind == .water ? .literUnit(with: .milli) : kind == .caffeine ? .gramUnit(with: .milli) : .kilocalorie()
                let value = sample.quantity.doubleValue(for: unit)
                guard value.isFinite, value >= 0 else { continue }
                let zone = (sample.metadata?[HKMetadataKeyTimeZone] as? String).flatMap(TimeZone.init(identifier:)) ?? .current
                events.append(HealthEvent(id: sample.uuid, kind: kind, date: sample.startDate,
                    timezone: zone.identifier, offsetSeconds: zone.secondsFromGMT(for: sample.startDate),
                    updatedAt: sample.endDate, title: kind == .meal ? "Питание" : kind.title, amount: value,
                    unit: kind == .water ? "мл" : kind == .caffeine ? "мг" : "ккал", source: sample.sourceRevision.source.name,
                    externalID: sample.uuid.uuidString))
            }
            for key in days.keys { days[key]?.sleepEnd = nil }
            for (metric, (type, unit)) in Self.dailyTypes {
                let collection = try await HKStatisticsCollectionQueryDescriptor(
                    predicate: .quantitySample(type: type, predicate: window), options: [.cumulativeSum, .separateBySource],
                    anchorDate: calendar.startOfDay(for: now), intervalComponents: DateComponents(day: 1)).result(for: health)
                for bucket in collection.statistics() where bucket.startDate >= start && bucket.startDate <= now {
                    guard let value = bucket.sumQuantity()?.doubleValue(for: unit), value.isFinite, value >= 0 else { continue }
                    var day = days[bucket.startDate] ?? DailyHealth(date: bucket.startDate)
                    day.values[metric] = value
                    day.sources[metric] = (bucket.sources ?? []).map { $0.name + "|" + $0.bundleIdentifier }.sorted().joined(separator: ", ")
                    day.counts[metric] = nil // Statistics are day aggregates, not raw sample counts.
                    days[day.date] = day
                }
            }
            let sleepSnapshot = try await sleep
            for night in sleepSnapshot.days where night.date >= start {
                var day = days[night.date] ?? DailyHealth(date: night.date)
                if let sleep = night.sleep {
                    day.values[.sleepMinutes] = sleep.sleptSeconds / 60
                    day.sources[.sleepMinutes] = sleep.sourceName + "|" + sleep.sourceID
                    day.counts[.sleepMinutes] = sleep.spans.filter(\.phase.isSleep).count
                    day.sleepStart = sleep.start; day.sleepEnd = sleep.end
                }
                for (metric, reading) in night.readings {
                    let key: HealthMeasure
                    switch metric {
                    case .hrv: key = .hrv
                    case .restingPulse: key = .restingPulse
                    case .sleepingPulse: key = .sleepingPulse
                    case .respiration: key = .respiration
                    case .oxygen: key = .oxygen
                    case .wristTemperature: key = .temperature
                    }
                    day.values[key] = reading.value; day.sources[key] = reading.sourceName + "|" + reading.sourceID
                    day.counts[key] = reading.count
                }
                days[day.date] = day
            }
            guard generation == request, journal.journal.healthEnabled, !Task.isCancelled else { return }
            try daily.importHealth(from: start, to: now, events: events, days: Array(days.values))
            daily.importMessage = "Обновлено \(now.formatted(date: .omitted, time: .shortened)). Первый импорт охватывает до года; история продолжает накапливаться локально."
        } catch {
            guard generation == request else { return }
            issue = "Не удалось обновить Health OS. Сохранённая история доступна. Потяните экран вниз, чтобы повторить."
        }
    }

    func syncIntake(_ daily: HealthOSStore) async {
        guard !busy, daily.settings.writeIntakeToHealth else { return }
        busy = true; defer { busy = false }
        do { try await exportPending(daily) }
        catch { issue = "Вода или кофеин сохранены локально. Отправку в «Здоровье» повторим при открытии приложения." }
    }

    func disconnect(_ daily: HealthOSStore) {
        generation = UUID(); daily.clearImported()
    }

    private func exportPending(_ daily: HealthOSStore) async throws {
        guard daily.settings.writeIntakeToHealth else { return }
        for event in daily.archive.events where event.isLocal && event.needsHealthSync && [.water, .caffeine].contains(event.kind) {
            guard daily.settings.writeIntakeToHealth, !Task.isCancelled else { return }
            let type = event.kind == .water ? Self.water : Self.caffeine
            guard health.authorizationStatus(for: type) == .sharingAuthorized else { continue }
            let predicate = HKQuery.predicateForObjects(withMetadataKey: Self.syncKey, allowedValues: [event.id.uuidString])
            _ = try await health.deleteObjects(of: type, predicate: predicate)
            if !event.deleted, let amount = event.amount {
                let unit: HKUnit = event.kind == .water ? .literUnit(with: .milli) : .gramUnit(with: .milli)
                let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: amount), start: event.date, end: event.date,
                    metadata: [Self.syncKey: event.id.uuidString, HKMetadataKeySyncIdentifier: event.id.uuidString,
                               HKMetadataKeySyncVersion: Int(event.updatedAt.timeIntervalSince1970 * 1000), HKMetadataKeyWasUserEntered: true])
                try await health.save(sample)
            }
            try daily.markSynced(event)
        }
    }
    private static func source(_ sample: HKSample) -> String { sample.sourceRevision.source.name + "|" + sample.sourceRevision.source.bundleIdentifier }
    #else
    func authorize(_ journal: JournalStore, daily: HealthOSStore, write: Bool = false) async { issue = "Для синхронизации нужен iPhone с доступом к Apple «Здоровью»." }
    func refresh(_ journal: JournalStore, daily: HealthOSStore, force: Bool = false, fullHistory: Bool = false) async {}
    func syncIntake(_ daily: HealthOSStore) async {}
    func disconnect(_ daily: HealthOSStore) { daily.clearImported() }
    #endif
}
