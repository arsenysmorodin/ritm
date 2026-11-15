import Foundation
import Observation
#if os(iOS) && RITM_HEALTHKIT
import HealthKit
#endif

@MainActor @Observable final class HealthConnection {
    var steps: Int?
    var activeEnergy: Int?
    var isBusy = false
    var isReading = false
    var issue: String?
    private(set) var exportIssue: (id: UUID, message: String)?
    private var refreshID = UUID()

    #if os(iOS) && RITM_HEALTHKIT
    private let store = HKHealthStore()
    private let stepsType = HKQuantityType(.stepCount)
    private let energyType = HKQuantityType(.activeEnergyBurned)
    private let workoutType = HKObjectType.workoutType()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    private(set) var canWrite = false
    var availabilityMessage: String { "На этом устройстве Apple «Здоровье» недоступно." }

    func connect(_ journal: JournalStore) async {
        guard isAvailable, !isBusy else { return }
        isBusy = true
        issue = nil
        do {
            try await store.requestAuthorization(toShare: [workoutType], read: [stepsType, energyType])
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
        isReading = false
    }
}
