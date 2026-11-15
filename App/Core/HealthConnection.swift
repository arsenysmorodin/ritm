import Foundation
import Observation
#if os(iOS) && RITM_HEALTHKIT
import HealthKit
#endif

@MainActor @Observable final class HealthConnection {
    var steps: Int?
    var activeEnergy: Int?
    private(set) var weightHistory: [WeightPoint] = []
    private(set) var additionalPermissionsPending = false
    var isBusy = false
    var isReading = false
    var issue: String?
    private(set) var exportIssue: (id: UUID, message: String)?
    private var refreshID = UUID()

    #if os(iOS) && RITM_HEALTHKIT
    private let store = HKHealthStore()
    private let stepsType = HKQuantityType(.stepCount)
    private let energyType = HKQuantityType(.activeEnergyBurned)
    private let massType = HKQuantityType(.bodyMass)
    private let pulseType = HKQuantityType(.heartRate)
    private var reads: Set<HKObjectType> { [stepsType, energyType, massType, pulseType] }
    private let workoutType = HKObjectType.workoutType()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    private(set) var canWrite = false
    var availabilityMessage: String { "На этом устройстве Apple «Здоровье» недоступно." }

    func connect(_ journal: JournalStore) async {
        guard isAvailable, !isBusy else { return }
        isBusy = true
        issue = nil
        do {
            try await store.requestAuthorization(toShare: [workoutType], read: reads)
            journal.change { $0.healthEnabled = true }
        } catch {
            issue = "Не удалось открыть доступ к «Здоровью». Проверьте разрешения и попробуйте снова."
        }
        isBusy = false
        await refresh(journal)
        await exportPending(journal)
    }

    func refresh(_ journal: JournalStore) async {
        guard isAvailable, journal.journal.healthEnabled else { clearMetrics(); return }
        updateWriteAccess()
        await refreshPermissionStatus()
        guard journal.journal.healthEnabled else { return }
        let request = UUID()
        refreshID = request
        isReading = true
        let now = Date.now
        let window = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: now), end: now, options: .strictStartDate)
        async let stepTotal = total(stepsType, unit: .count(), window: window)
        async let energyTotal = total(energyType, unit: .kilocalorie(), window: window)
        let result = await (stepTotal, energyTotal)
        guard refreshID == request, journal.journal.healthEnabled else { return }
        steps = result.0
        activeEnergy = result.1
        isReading = false
    }

    func refreshWeight(_ journal: JournalStore) async {
        guard isAvailable, journal.journal.healthEnabled else { return }
        await refreshPermissionStatus()
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -364, to: calendar.startOfDay(for: .now)) ?? .distantPast
        let filter = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: massType, predicate: filter)], sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = (try? await descriptor.result(for: store)) ?? []
        guard journal.journal.healthEnabled, !Task.isCancelled else { return }
        var daily: [Date: WeightPoint] = [:]
        for sample in samples {
            let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            guard kg.isFinite, kg > 0 else { continue }
            daily[calendar.startOfDay(for: sample.startDate)] = WeightPoint(id: sample.uuid, date: sample.startDate, kilograms: kg)
        }
        weightHistory = daily.values.sorted { $0.date < $1.date }
    }

    private func refreshPermissionStatus() async {
        additionalPermissionsPending = (try? await store.statusForAuthorizationRequest(toShare: [workoutType], read: reads)) == .shouldRequest
    }

    func recentPulse(from start: Date, through end: Date) async -> [PulsePoint] {
        guard isAvailable else { return [] }
        let filter = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate, .strictEndDate])
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: pulseType, predicate: filter)], sortDescriptors: [SortDescriptor(\.endDate)])
        let samples = (try? await descriptor.result(for: store)) ?? []
        let unit = HKUnit.count().unitDivided(by: .minute())
        return samples.compactMap { sample in
            let bpm = sample.quantity.doubleValue(for: unit)
            guard (20...300).contains(bpm) else { return nil }
            return PulsePoint(date: sample.endDate, bpm: Int(bpm.rounded()))
        }
    }

    private func total(_ type: HKQuantityType, unit: HKUnit, window: NSPredicate) async -> Int? {
        let query = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: type, predicate: window), options: .cumulativeSum)
        guard let sample = try? await query.result(for: store), let sum = sample.sumQuantity() else { return nil }
        return Int(sum.doubleValue(for: unit).rounded())
    }

    func requestExport(_ id: UUID, from journal: JournalStore) async {
        guard isAvailable, journal.journal.healthEnabled, !isBusy,
              let record = journal.journal.records.first(where: { $0.id == id && !$0.healthExported }) else { return }
        if !record.awaitsHealthExport {
            guard journal.change({ state in
                if let index = state.records.firstIndex(where: { $0.id == id }) {
                    state.records[index].healthExportRequestedAt = .now
                }
            }) else { return }
        }
        await exportPending(journal, first: id)
    }

    func exportPending(_ journal: JournalStore, first: UUID? = nil) async {
        guard isAvailable, !isBusy, journal.journal.healthEnabled,
              journal.journal.records.contains(where: \.awaitsHealthExport) else { return }
        updateWriteAccess()
        guard canWrite else {
            if let first {
                exportIssue = (first, "Откройте вкладку «Здоровье» в «Ритме», чтобы узнать, как разрешить запись тренировок.")
            }
            return
        }
        isBusy = true
        defer { isBusy = false }
        var attempted = Set<UUID>()
        while journal.journal.healthEnabled {
            let pending = journal.journal.records.filter { $0.awaitsHealthExport && !attempted.contains($0.id) }
            let oldest = pending.min {
                ($0.healthExportRequestedAt ?? $0.endedAt) < ($1.healthExportRequestedAt ?? $1.endedAt)
            }
            guard let record = pending.first(where: { $0.id == first }) ?? oldest else { return }
            attempted.insert(record.id)
            do {
                try await saveIfNeeded(record)
                guard journal.change({ state in
                    guard let index = state.records.firstIndex(where: { $0.id == record.id }) else { return }
                    state.records[index].healthExported = true
                    state.records[index].healthExportRequestedAt = nil
                }) else { return }
                if exportIssue?.id == record.id { exportIssue = nil }
            } catch {
                exportIssue = (record.id, "Отправка пока не удалась. «Ритм» повторит её при следующем открытии приложения.")
                updateWriteAccess()
                if !canWrite { return }
            }
        }
    }

    private func updateWriteAccess() {
        canWrite = isAvailable && store.authorizationStatus(for: workoutType) == .sharingAuthorized
    }

    private func saveIfNeeded(_ record: WorkoutRecord) async throws {
        let id = record.id.uuidString
        // Read only this app’s own sample, in case the previous save finished before the journal updated.
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [id])
        ])
        let existing = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [], limit: 1)
        if let matches = try? await existing.result(for: store), !matches.isEmpty { return }

        let configuration = HKWorkoutConfiguration()
        configuration.locationType = .indoor
        switch record.kind {
        case .strength: configuration.activityType = .traditionalStrengthTraining
        case .mobility: configuration.activityType = .flexibility
        case .intervals: configuration.activityType = .highIntensityIntervalTraining
        }
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: nil)
        try await builder.beginCollection(at: record.startedAt)
        try await builder.addMetadata([
            HKMetadataKeySyncIdentifier: id,
            HKMetadataKeySyncVersion: 1,
            HKMetadataKeyIndoorWorkout: true
        ])
        try await builder.endCollection(at: record.endedAt)
        _ = try await builder.finishWorkout()
    }
    #else
    var isAvailable: Bool { false }
    var canWrite: Bool { false }
    var availabilityMessage: String { "Подключение доступно на iPhone в сборке с Apple «Здоровьем»." }
    func connect(_ journal: JournalStore) async {}
    func refresh(_ journal: JournalStore) async {}
    func refreshWeight(_ journal: JournalStore) async {}
    func recentPulse(from start: Date, through end: Date) async -> [PulsePoint] { [] }
    func requestExport(_ id: UUID, from journal: JournalStore) async {}
    func exportPending(_ journal: JournalStore, first: UUID? = nil) async {}
    #endif

    func disconnect(_ journal: JournalStore) {
        if journal.change({ $0.healthEnabled = false }) {
            clearMetrics()
            issue = nil
            exportIssue = nil
        }
    }

    private func clearMetrics() {
        refreshID = UUID()
        steps = nil
        activeEnergy = nil
        weightHistory = []
        additionalPermissionsPending = false
        isReading = false
    }
}
