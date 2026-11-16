#if os(iOS) && RITM_HEALTHKIT
import HealthKit

@MainActor
final class HealthWidgetReader {
    private let store = HKHealthStore()
    private var observer: HKObserverQuery?

    private static let pulse = HKQuantityType(.heartRate)
    private static let hrv = HKQuantityType(.heartRateVariabilitySDNN)
    private static let nutrition: [Nutrient: HKQuantityType] = [
        .energy: HKQuantityType(.dietaryEnergyConsumed), .protein: HKQuantityType(.dietaryProtein),
        .fat: HKQuantityType(.dietaryFatTotal), .carbs: HKQuantityType(.dietaryCarbohydrates),
        .fiber: HKQuantityType(.dietaryFiber), .sugar: HKQuantityType(.dietarySugar),
        .saturatedFat: HKQuantityType(.dietaryFatSaturated), .sodium: HKQuantityType(.dietarySodium)
    ]

    static var types: [HKQuantityType] { [pulse, hrv] + Array(nutrition.values) }

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
    }

    func enableBackgroundUpdates() {
        for type in Self.types {
            store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
        }
    }

    func stop() {
        if let observer { store.stop(observer) }
        observer = nil
        for type in Self.types {
            store.disableBackgroundDelivery(for: type) { _, _ in }
        }
    }

    func snapshot(now: Date = .now, calendar: Calendar = .current) async throws -> HealthWidgetSnapshot {
        let day = calendar.startOfDay(for: now)
        let last48Hours = now.addingTimeInterval(-48 * 3600)
        let heartWindow = HKQuery.predicateForSamples(withStart: last48Hours, end: now, options: [.strictStartDate, .strictEndDate])
        let foodWindow = HKQuery.predicateForSamples(withStart: day, end: now, options: .strictStartDate)
        async let heartSamples = samples(for: [Self.pulse, Self.hrv], window: heartWindow)
        async let foodSamples = samples(for: Array(Self.nutrition.values), window: foodWindow)
        let (heart, food) = try await (heartSamples, foodSamples)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let milliseconds = HKUnit.secondUnit(with: .milli)
        let pulse = heart.filter { $0.quantityType == Self.pulse }.map {
            CardiacReading(date: $0.endDate, value: $0.quantity.doubleValue(for: bpm))
        }
        let variability = heart.filter { $0.quantityType == Self.hrv }.map {
            CardiacReading(date: $0.endDate, value: $0.quantity.doubleValue(for: milliseconds))
        }
        let kinds = Dictionary(uniqueKeysWithValues: Self.nutrition.map { ($0.value, $0.key) })
        var totals: [Nutrient: Double] = [:]
        for sample in food {
            let source = sample.sourceRevision.source
            guard HealthWidgetSnapshot.isFatSecret(bundleID: source.bundleIdentifier, sourceName: source.name),
                  let kind = kinds[sample.quantityType] else { continue }
            let unit: HKUnit = kind == .energy ? .kilocalorie() : kind == .sodium ? .gramUnit(with: .milli) : .gram()
            let amount = sample.quantity.doubleValue(for: unit)
            if amount.isFinite && amount >= 0 { totals[kind, default: 0] += amount }
        }
        return HealthWidgetSnapshot(day: day,
                                    pulse: CardiacSeries(pulse, from: day, through: now),
                                    hrv: CardiacSeries(variability, from: day, through: now),
                                    nutrition: totals)
    }

    private func samples(for types: [HKQuantityType], window: NSPredicate) async throws -> [HKQuantitySample] {
        let predicates = types.map { HKSamplePredicate.quantitySample(type: $0, predicate: window) }
        let descriptor = HKSampleQueryDescriptor(predicates: predicates, sortDescriptors: [])
        return try await descriptor.result(for: store)
    }
}
#endif
