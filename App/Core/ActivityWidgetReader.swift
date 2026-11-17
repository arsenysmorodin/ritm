#if os(iOS) && RITM_HEALTHKIT
import HealthKit

@MainActor
final class ActivityWidgetReader {
    private let store = HKHealthStore()
    private var observer: HKObserverQuery?

    private static let steps = HKQuantityType(.stepCount)
    private static let energy = HKQuantityType(.activeEnergyBurned)
    private static let bodyMass = HKQuantityType(.bodyMass)
    static var types: [HKQuantityType] { [steps, energy, bodyMass] }

    func start(onUpdate: @escaping @MainActor () async -> Void) {
        guard observer == nil else { return }
        let query = HKObserverQuery(queryDescriptors: Self.types.map { HKQueryDescriptor(sampleType: $0, predicate: nil) }) {
            _, _, complete, error in
            Task { @MainActor in
                defer { complete() }
                if error == nil { await onUpdate() }
            }
        }
        observer = query
        store.execute(query)
        enableBackgroundUpdates()
    }

    func enableBackgroundUpdates() {
        for type in Self.types {
            store.enableBackgroundDelivery(for: type, frequency: type == Self.bodyMass ? .immediate : .hourly) { _, _ in }
        }
    }

    func stop() {
        if let observer { store.stop(observer) }
        observer = nil
        for type in Self.types { store.disableBackgroundDelivery(for: type) { _, _ in } }
    }

    func snapshot(now: Date = .now, calendar: Calendar = .current) async throws -> ActivityWidgetSnapshot {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -6, to: today) else {
            return ActivityWidgetSnapshot(days: [], weights: [])
        }
        let week = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictEndDate)
        async let steps = daily(Self.steps, unit: .count(), in: week, from: start, through: now, anchor: today)
        async let energy = daily(Self.energy, unit: .kilocalorie(), in: week, from: start, through: now, anchor: today)
        async let weights = weightHistory(at: now, calendar: calendar)
        let (stepDays, energyDays, history) = try await (steps, energy, weights)
        let days = Set(stepDays.keys).union(energyDays.keys).sorted().map {
            ActivityDay(date: $0, steps: stepDays[$0], activeEnergy: energyDays[$0])
        }
        return ActivityWidgetSnapshot(days: days, weights: history)
    }

    func weightHistory(at now: Date = .now, calendar: Calendar = .current) async throws -> [WeightPoint] {
        let start = calendar.date(byAdding: .day, value: -364, to: calendar.startOfDay(for: now)) ?? .distantPast
        let window = HKQuery.predicateForSamples(withStart: start, end: now, options: [.strictStartDate, .strictEndDate])
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: Self.bodyMass, predicate: window)], sortDescriptors: [])
        let unit = HKUnit.gramUnit(with: .kilo)
        let samples = try await descriptor.result(for: store)
        return WeightPoint.latestPerDay(samples.map {
            WeightPoint(id: $0.uuid, date: $0.startDate, kilograms: $0.quantity.doubleValue(for: unit))
        }, calendar: calendar)
    }

    private func daily(_ type: HKQuantityType, unit: HKUnit, in window: NSPredicate,
                       from start: Date, through end: Date, anchor: Date) async throws -> [Date: Int] {
        let descriptor = HKStatisticsCollectionQueryDescriptor(predicate: .quantitySample(type: type, predicate: window),
            options: .cumulativeSum, anchorDate: anchor, intervalComponents: DateComponents(day: 1))
        let collection = try await descriptor.result(for: store)
        let buckets = collection.statistics().filter { (start...end).contains($0.startDate) }
        var values: [Date: Int] = [:]
        for bucket in buckets {
            guard let raw = bucket.sumQuantity()?.doubleValue(for: unit), raw >= 0,
                  let value = Int(exactly: raw.rounded()) else { continue }
            values[bucket.startDate] = value
        }
        return values
    }
}
#endif
