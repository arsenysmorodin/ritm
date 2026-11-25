import Foundation
import Observation
import WatchKit

@MainActor @Observable final class WatchHealthStore {
    let link: WatchLink
    private(set) var snapshot: WatchHealthSnapshot?
    private(set) var outbox = WatchHealthOutbox()
    private(set) var refreshing = false
    private(set) var lastCheckIn: WatchHealthAction?
    var message: String?
    private var sending = Set<UUID>()
    private let cacheKey = "ritm.watch.health.cache.v1"
    private let outboxKey = "ritm.watch.health.outbox.v1"
    private let checkInKey = "ritm.watch.health.check-in.v1"

    init(link: WatchLink) {
        self.link = link
        snapshot = Self.load(WatchHealthSnapshot.self, key: cacheKey)
        outbox = Self.load(WatchHealthOutbox.self, key: outboxKey) ?? WatchHealthOutbox()
        lastCheckIn = Self.load(WatchHealthAction.self, key: checkInKey)
        link.onHealthSnapshot = { [weak self] in self?.receive($0) }
        link.onHealthReceipt = { [weak self] in self?.acknowledge($0) }
        link.onHealthActivated = { [weak self] in self?.refresh() }
        link.onHealthTransferFailed = { [weak self] action in
            self?.sending.remove(action.id)
            self?.message = "Запись сохранена на часах. Повторим передачу при подключении."
        }
        if let current = link.companionHealth { receive(current) }
        if link.active { flush() }
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--watch-health-demo") { loadDemo() }
        #endif
    }

    var pending: Int { outbox.actions.count }
    var currentCheckIn: WatchHealthAction? {
        let local = lastCheckIn.flatMap { check in outbox.actions.contains(where: { $0.id == check.id }) ? check : nil }
        return [snapshot?.checkIn, local].compactMap { $0 }
            .filter { Calendar.current.isDateInToday($0.date) }.max { $0.date < $1.date }
    }

    func addWater(_ amount: Int) { save(WatchHealthAction(kind: .water, amount: amount)) }

    @discardableResult func checkIn(_ ratings: [String: Int]) -> Bool {
        let action = WatchHealthAction(kind: .checkIn, ratings: ratings)
        guard action.isValid(at: .now) else { return false }
        lastCheckIn = action
        persist(action, key: checkInKey)
        save(action)
        return true
    }

    func refresh() {
        flush()
        guard link.reachable, !refreshing else {
            if !link.reachable { message = "Откройте «Ритм» на iPhone для обновления обзора." }
            return
        }
        refreshing = true
        link.send(.requestHealth) { [weak self] ok in
            self?.refreshing = false
            if !ok { self?.message = "iPhone пока не передал данные. Записи на часах сохранены." }
        }
    }

    private func save(_ action: WatchHealthAction) {
        guard action.isValid(at: .now) else { return }
        outbox.append(action)
        persist(outbox, key: outboxKey)
        message = nil
        WKInterfaceDevice.current().play(.success)
        flush()
    }

    private func receive(_ value: WatchHealthSnapshot?) {
        snapshot = value
        if value?.readable == true { message = nil }
        if let value { persist(value, key: cacheKey) }
        else { UserDefaults.standard.removeObject(forKey: cacheKey) }
    }

    private func acknowledge(_ receipt: WatchHealthReceipt) {
        sending.remove(receipt.id)
        outbox.acknowledge(receipt)
        persist(outbox, key: outboxKey)
        if receipt.accepted, lastCheckIn?.id == receipt.id {
            lastCheckIn = nil
            UserDefaults.standard.removeObject(forKey: checkInKey)
        }
        if !receipt.accepted { message = "iPhone пока не сохранил запись. Она осталась на часах; обновите связь позже." }
    }

    private func flush() {
        guard link.active else { return }
        for action in outbox.actions where !sending.contains(action.id) {
            if link.reachable {
                sending.insert(action.id)
                link.send(.health(action)) { [weak self] accepted in
                    guard let self else { return }
                    if accepted { acknowledge(WatchHealthReceipt(id: action.id, accepted: true)) }
                    else {
                        sending.remove(action.id)
                        queue(action)
                    }
                }
            } else { queue(action) }
        }
    }

    private func queue(_ action: WatchHealthAction) {
        if link.queuedHealthIDs.contains(action.id) { return }
        _ = link.queue(.health(action))
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    #if DEBUG && targetEnvironment(simulator)
    private func loadDemo() {
        let now = Date.now
        snapshot = WatchHealthSnapshot(day: Calendar.current.startOfDay(for: now), healthEnabled: true, metrics: [
            .init(kind: .sleep, value: 472, measuredAt: now.addingTimeInterval(-3600)),
            .init(kind: .hrv, value: 64, measuredAt: now.addingTimeInterval(-3600), rangeLower: 48, rangeUpper: 72, historyDays: 21),
            .init(kind: .pulse, value: 68, measuredAt: now.addingTimeInterval(-120)),
            .init(kind: .steps, value: 6280, measuredAt: now),
            .init(kind: .activeEnergy, value: 418, measuredAt: now),
            .init(kind: .protein, value: 96, measuredAt: now),
            .init(kind: .fiber, value: 23, measuredAt: now)
        ], waterML: 1250, supplementsTaken: 2, supplementsPlanned: 3, nextSupplement: "Витамин D")
    }
    #endif
}
