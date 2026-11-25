import Foundation

/// Owns the phone-side stores even when SwiftUI has no active scene.
@MainActor final class PhoneCompanion {
    let daily: HealthOSStore
    let bridge: HealthOSBridge
    private let journal: JournalStore
    private let health: HealthConnection
    private let link: WatchLink
    private var intakeTask: Task<Void, Never>?

    init(journal: JournalStore, health: HealthConnection, link: WatchLink, daily: HealthOSStore, bridge: HealthOSBridge) {
        self.journal = journal; self.health = health; self.link = link
        self.daily = daily; self.bridge = bridge
        link.onEvent = { [weak self] event in self?.receive(event) ?? false }
        daily.onChange = { [weak self] in self?.dailyChanged() }
        health.onDataUpdate = { [weak self] in await self?.healthChanged() }
        publish()
    }

    func publish() {
        daily.reload()
        link.publish(journal.watchSnapshot)
        link.publishHealth(CompanionHealthLogic.snapshot(archive: daily.archive, readable: daily.isReadable,
            healthEnabled: journal.journal.healthEnabled, recovery: health.recoverySnapshot, heart: health.widgetSnapshot,
            activity: WidgetStorage.load(ActivityWidgetSnapshot.self, file: ActivityWidgetSnapshot.file)))
    }

    private func receive(_ event: WatchEvent) -> Bool {
        switch event {
        case .health(let action):
            let accepted = daily.receiveWatchHealth(action)
            publish()
            return accepted
        case .requestHealth:
            publish()
            Task { [weak self] in
                guard let self else { return }
                if journal.journal.healthEnabled { await health.refreshWidgetData(journal) }
                publish()
            }
            return daily.isReadable
        default:
            let accepted = journal.receiveWatch(event)
            link.publish(journal.watchSnapshot)
            return accepted
        }
    }

    private func dailyChanged() {
        publish()
        intakeTask?.cancel()
        intakeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            if journal.journal.healthEnabled { await bridge.syncIntake(daily) }
            _ = await HealthOSNotifications.update(daily, healthEnabled: journal.journal.healthEnabled, recovery: health.recoverySnapshot)
        }
    }

    private func healthChanged() async {
        publish()
        _ = await HealthOSNotifications.update(daily, healthEnabled: journal.journal.healthEnabled, recovery: health.recoverySnapshot)
    }
}
