import Foundation
import UserNotifications

@MainActor enum HealthOSNotifications {
    private static var generation = UUID()
    private static var worker: Task<String?, Never>?
    private static var permissionPending = false
    private static let receiptsKey = "ritm.proactive.receipts"
    static func supplementID(_ id: UUID, slot: Date) -> String { "ritm.health.supplement.\(id).\(Int(slot.timeIntervalSince1970))" }

    static func update(_ store: HealthOSStore, requestPermission: Bool = false, healthEnabled: Bool = false,
                       recovery: RecoverySnapshot? = nil) async -> String? {
        let token = UUID(); generation = token
        permissionPending = permissionPending || requestPermission
        let previous = worker
        let task = Task { @MainActor () -> String? in
            _ = await previous?.value
            guard generation == token else { return nil }
            let ask = permissionPending; permissionPending = false
            return await perform(store, requestPermission: ask, healthEnabled: healthEnabled, recovery: recovery)
        }
        worker = task
        let result = await task.value
        if requestPermission, generation != token, let latest = worker { return await latest.value }
        return result
    }

    private static func perform(_ store: HealthOSStore, requestPermission: Bool, healthEnabled: Bool,
                                recovery: RecoverySnapshot?) async -> String? {
        guard store.isReadable else { return requestPermission ? "Health OS пока недоступна. Повторите с разблокированным iPhone." : nil }
        let center = UNUserNotificationCenter.current()
        let settings = store.settings
        let enabled = !settings.waterReminderTimes.isEmpty || settings.supplementReminders || settings.proactive.enabled
        var authorization = await center.notificationSettings()
        if enabled, requestPermission, authorization.authorizationStatus == .notDetermined {
            do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
            catch { return "Не удалось запросить уведомления. Повторите сохранение." }
            authorization = await center.notificationSettings()
        }
        let previous = await center.pendingNotificationRequests()
        let now = Date.now, calendar = Calendar.current
        let change = healthEnabled ? ProactiveNotificationPlanner.healthChange(settings: settings.proactive,
            snapshot: recovery ?? WidgetStorage.load(RecoverySnapshot.self, file: RecoverySnapshot.file), now: now) : nil
        let retainedChange = change.flatMap { candidate in previous.first { $0.identifier == candidate.id }?.identifier }
        center.removePendingNotificationRequests(withIdentifiers: previous.filter {
            $0.identifier.hasPrefix("ritm.health.") && $0.identifier != retainedChange
        }.map(\.identifier))
        guard enabled else { return nil }
        guard [.authorized, .provisional, .ephemeral].contains(authorization.authorizationStatus) else {
            return requestPermission ? "Разрешите уведомления в Настройки → Уведомления → Ритм. Журнал сохранён." : nil
        }
        var requests: [(Date, UNNotificationRequest)] = []
        var receipts = loadReceipts().filter { now.timeIntervalSince($0.value) < 8 * 86400 }
        let planned = ProactiveNotificationPlanner.scheduled(settings: settings.proactive, events: store.events, now: now)
        for plan in planned { requests.append((plan.date, request(plan, calendar: calendar))) }
        if let change, retainedChange == nil, ProactiveNotificationPlanner.mayDeliver(change, receipts: receipts, now: now) {
            requests.append((change.date, request(change, calendar: calendar)))
        }
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
            do {
                try await center.add(request)
                if request.identifier == change?.id {
                    receipts[request.identifier] = now
                    if let data = try? JSONEncoder().encode(receipts) { UserDefaults.standard.set(data, forKey: receiptsKey) }
                }
            }
            catch { return "Часть напоминаний не удалось запланировать. Откройте приложение и повторите сохранение." }
        }
        return nil
    }

    private static func loadReceipts() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: receiptsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Date].self, from: data)) ?? [:]
    }

    private static func request(_ plan: ProactiveNotification, calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = plan.title; content.body = plan.body; content.sound = .default
        content.userInfo = ["ritmRoute": plan.route]
        let trigger: UNNotificationTrigger
        if let minute = plan.repeatMinute {
            trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: minute / 60, minute: minute % 60), repeats: true)
        } else if plan.kind == .healthChange {
            content.interruptionLevel = .passive
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        } else {
            trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.date), repeats: false)
        }
        return UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger)
    }
}
