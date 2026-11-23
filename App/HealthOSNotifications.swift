import Foundation
import UserNotifications

@MainActor enum HealthOSNotifications {
    private static var generation = UUID()
    static func supplementID(_ id: UUID, slot: Date) -> String { "ritm.health.supplement.\(id).\(Int(slot.timeIntervalSince1970))" }

    static func update(_ store: HealthOSStore, requestPermission: Bool = false) async -> String? {
        let token = UUID(); generation = token
        let center = UNUserNotificationCenter.current()
        let settings = store.settings
        let enabled = !settings.waterReminderTimes.isEmpty || settings.supplementReminders
        var authorization = await center.notificationSettings()
        if enabled, requestPermission, authorization.authorizationStatus == .notDetermined {
            do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
            catch { return "Не удалось запросить уведомления. Повторите сохранение." }
            authorization = await center.notificationSettings()
        }
        let previous = await center.pendingNotificationRequests()
        guard generation == token else { return nil }
        center.removePendingNotificationRequests(withIdentifiers: previous.filter { $0.identifier.hasPrefix("ritm.health.") }.map(\.identifier))
        guard enabled else { return nil }
        guard [.authorized, .provisional, .ephemeral].contains(authorization.authorizationStatus) else {
            return requestPermission ? "Разрешите уведомления в Настройки → Уведомления → Ритм. Журнал сохранён." : nil
        }
        var requests: [(Date, UNNotificationRequest)] = []
        let calendar = Calendar.current, now = Date.now
        for minute in settings.waterReminderTimes {
            let content = UNMutableNotificationContent()
            content.title = "Вода"; content.body = "Отметьте выпитую воду в «Ритме»."; content.sound = .default
            content.userInfo = ["ritmRoute": "water"]
            let parts = DateComponents(hour: minute / 60, minute: minute % 60)
            let next = calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime) ?? now
            requests.append((next, UNNotificationRequest(identifier: "ritm.health.water.\(minute)", content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: true))))
        }
        if settings.supplementReminders {
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
                for supplement in store.supplements {
                    for slot in supplement.slots(on: day) where slot > now && !HealthOSLogic.completedSlot(slot, supplement: supplement.id, events: store.events) {
                        let content = UNMutableNotificationContent()
                        content.title = supplement.name; content.body = "По вашему расписанию: \(HealthEvent.number(supplement.servings)) порц."
                        content.sound = .default; content.userInfo = ["ritmRoute": "supplements"]
                        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: slot)
                        requests.append((slot, UNNotificationRequest(identifier: supplementID(supplement.id, slot: slot), content: content,
                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))))
                    }
                }
            }
        }
        // Leave room for the rest timer and other system-delivered notifications.
        for (_, request) in requests.sorted(by: { $0.0 < $1.0 }).prefix(40) {
            guard generation == token else { return nil }
            do { try await center.add(request) }
            catch { return "Часть напоминаний не удалось запланировать. Откройте приложение и повторите сохранение." }
        }
        return nil
    }
}
