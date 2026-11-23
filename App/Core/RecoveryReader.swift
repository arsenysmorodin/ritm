#if os(iOS) && RITM_HEALTHKIT
import HealthKit

@MainActor
final class RecoveryReader {
    private let store = HKHealthStore()
    private var observer: HKObserverQuery?

    private static let sleep = HKCategoryType(.sleepAnalysis)
    private static let perMinute = HKUnit.count().unitDivided(by: .minute())
    private static let quantities: [RecoveryMetric: (type: HKQuantityType, unit: HKUnit)] = [
        .hrv: (HKQuantityType(.heartRateVariabilitySDNN), .secondUnit(with: .milli)),
        .restingPulse: (HKQuantityType(.restingHeartRate), perMinute),
        .sleepingPulse: (HKQuantityType(.heartRate), perMinute),
        .respiration: (HKQuantityType(.respiratoryRate), perMinute),
        .oxygen: (HKQuantityType(.oxygenSaturation), .percent()),
        .wristTemperature: (HKQuantityType(.appleSleepingWristTemperature), .degreeCelsius())
    ]

    static var types: [HKSampleType] { [sleep] + quantities.values.map(\.type) }
    private static var observed: [HKSampleType] {
        [sleep] + quantities.filter { $0.key != .sleepingPulse && $0.key != .hrv }.values.map(\.type)
    }

    func start(onUpdate: @escaping @MainActor () async -> Void) {
        guard observer == nil else { return }
        let query = HKObserverQuery(queryDescriptors: Self.observed.map { HKQueryDescriptor(sampleType: $0, predicate: nil) }) {
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
        for type in Self.observed {
            store.enableBackgroundDelivery(for: type, frequency: type == Self.sleep ? .immediate : .hourly) { _, _ in }
        }
    }

    func stop() {
        if let observer { store.stop(observer) }
        observer = nil
        for type in Self.observed {
            store.disableBackgroundDelivery(for: type) { _, _ in }
        }
    }

    func snapshot(now: Date = .now, calendar: Calendar = .current, historyDays: Int = 35) async throws -> RecoverySnapshot {
        let cutoff = calendar.date(byAdding: .day, value: -historyDays, to: calendar.startOfDay(for: now)) ?? now
        let window = HKQuery.predicateForSamples(withStart: cutoff, end: now, options: .strictEndDate)
        async let resting = quantities(for: [.restingPulse], window: window)
        let sleep = try await HKSampleQueryDescriptor(
            predicates: [.categorySample(type: Self.sleep, predicate: window)], sortDescriptors: []
        ).result(for: store)
        let sleepSamples = sleep.compactMap(Self.sleepSample)
        let nights = await Task.detached(priority: .utility) {
            SleepAnalysis.mainNights(sleepSamples, through: now, calendar: calendar)
        }.value

        let nightSamples: [RecoverySample]
        if nights.isEmpty {
            nightSamples = []
        } else {
            let windows = nights.map { HKQuery.predicateForSamples(withStart: $0.start, end: $0.end, options: []) }
            nightSamples = try await quantities(for: RecoveryMetric.allCases.filter(\.isNightly),
                                                window: NSCompoundPredicate(orPredicateWithSubpredicates: windows))
        }
        let allSamples = try await resting + nightSamples
        return await Task.detached(priority: .utility) {
            RecoverySnapshot.analyze(nights: nights, samples: allSamples, calendar: calendar)
        }.value
    }

    private func quantities(for metrics: [RecoveryMetric], window: NSPredicate) async throws -> [RecoverySample] {
        let types = Dictionary(uniqueKeysWithValues: metrics.compactMap { metric in
            Self.quantities[metric].map { ($0.type, (metric, $0.unit)) }
        })
        let query = HKSampleQueryDescriptor(
            predicates: types.keys.map { .quantitySample(type: $0, predicate: window) },
            sortDescriptors: []
        )
        return try await query.result(for: store).compactMap { sample in
            guard let (metric, unit) = types[sample.quantityType] else { return nil }
            let date = metric.isNightly
                ? sample.startDate.addingTimeInterval(sample.endDate.timeIntervalSince(sample.startDate) / 2)
                : sample.startDate
            let value = sample.quantity.doubleValue(for: unit) * (metric == .oxygen ? 100 : 1)
            return RecoverySample(metric: metric, date: date, value: value, source: Self.source(for: sample))
        }
    }

    private static func sleepSample(_ sample: HKCategorySample) -> SleepSample? {
        let phase: SleepPhase
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .inBed: phase = .inBed
        case .awake: phase = .awake
        case .asleepCore: phase = .core
        case .asleepDeep: phase = .deep
        case .asleepREM: phase = .rem
        case .asleepUnspecified: phase = .unspecified
        default: return nil
        }
        return SleepSample(span: SleepSpan(start: sample.startDate, end: sample.endDate, phase: phase),
                           source: source(for: sample))
    }

    private static func source(for sample: HKSample) -> RecoverySource {
        let revision = sample.sourceRevision
        let product = revision.productType ?? sample.device?.model ?? ""
        let manual = sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool == true
        let id = [revision.source.bundleIdentifier, product, manual ? "manual" : ""].joined(separator: "|")
        return RecoverySource(id: id, name: revision.source.name)
    }
}
#endif
