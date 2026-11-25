import Foundation

struct ProactiveNotificationSettings: Codable, Equatable {
    var morning = false
    var morningMinute = 9 * 60
    var checkIn = false
    var checkInMinute = 21 * 60
    var healthChanges = false
    var quietEnabled = true
    var quietStart = 22 * 60
    var quietEnd = 8 * 60
    var enabled: Bool { morning || checkIn || healthChanges }
    var isValid: Bool { [morningMinute, checkInMinute, quietStart, quietEnd].allSatisfy { (0..<1440).contains($0) } }

    func isQuiet(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard quietEnabled, quietStart != quietEnd else { return false }
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return quietStart < quietEnd ? (quietStart..<quietEnd).contains(minute) : minute >= quietStart || minute < quietEnd
    }

    func allowedMinute(_ minute: Int) -> Int {
        guard quietEnabled, quietStart != quietEnd else { return minute }
        let quiet = quietStart < quietEnd ? (quietStart..<quietEnd).contains(minute) : minute >= quietStart || minute < quietEnd
        return quiet ? quietEnd : minute
    }
}

struct ProactiveNotification: Equatable {
    enum Kind { case morning, checkIn, healthChange }
    let id: String
    let kind: Kind
    let title: String
    let body: String
    let date: Date
    let route: String
    var repeatMinute: Int?
}

enum ProactiveNotificationPlanner {
    static let prefix = "ritm.health.proactive."

    static func scheduled(settings: ProactiveNotificationSettings, events: [HealthEvent], now: Date = .now,
                          calendar: Calendar = .current) -> [ProactiveNotification] {
        guard settings.isValid else { return [] }
        var result: [ProactiveNotification] = []
        if settings.morning {
            let minute = settings.allowedMinute(settings.morningMinute)
            let parts = DateComponents(hour: minute / 60, minute: minute % 60)
            if let date = calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime) {
                result.append(.init(id: prefix + "morning", kind: .morning, title: "Обзор дня",
                    body: "Самочувствие, сон и показатели — в одном обзоре «Ритма».", date: date, route: "dashboard", repeatMinute: minute))
            }
        }
        if settings.checkIn {
            let minute = settings.checkInMinute
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                      HealthOSLogic.events(events, on: day, kind: .checkIn, calendar: calendar).isEmpty,
                      let desired = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day) else { continue }
                let date: Date
                if settings.isQuiet(desired, calendar: calendar) {
                    guard let end = calendar.nextDate(after: desired, matching: DateComponents(hour: settings.quietEnd / 60, minute: settings.quietEnd % 60), matchingPolicy: .nextTime) else { continue }
                    date = end
                } else { date = desired }
                guard date > now else { continue }
                result.append(.init(id: prefix + "checkin." + dayKey(day, calendar: calendar), kind: .checkIn,
                    title: "Как прошёл день?", body: "Добавьте отметку самочувствия в дневник «Ритма».", date: date, route: "check-in"))
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    /// Reuses the existing source-matched ranges. This is descriptive, not a diagnosis.
    static func healthChange(settings: ProactiveNotificationSettings, snapshot: RecoverySnapshot?,
                             now: Date = .now, calendar: Calendar = .current) -> ProactiveNotification? {
        guard settings.healthChanges, settings.isValid, !settings.isQuiet(now, calendar: calendar),
              let snapshot, let night = snapshot.recentNight(at: now, calendar: calendar),
              calendar.isDate(night.date, inSameDayAs: now), let sleep = night.sleep,
              now.timeIntervalSince(sleep.end) >= 30 * 60, now.timeIntervalSince(sleep.end) < 20 * 3600 else { return nil }
        let changed = RecoveryMetric.allCases.filter { metric in
            guard metric.isNightly, let reading = night.readings[metric],
                  let range = snapshot.range(for: metric, on: night, calendar: calendar), range.count >= 14 else { return false }
            switch range.position(for: reading.value) { case .within: return false; case .above, .below: return true }
        }
        guard changed.count >= 2 else { return nil }
        return .init(id: prefix + "change." + dayKey(night.date, calendar: calendar), kind: .healthChange,
            title: "Изменились ночные показатели",
            body: "Несколько показателей отличаются от вашего личного диапазона. Посмотрите подробности в «Ритме».",
            date: now, route: "recovery")
    }

    static func mayDeliver(_ notification: ProactiveNotification, receipts: [String: Date], now: Date) -> Bool {
        guard receipts[notification.id] == nil else { return false }
        return !receipts.contains { $0.key.hasPrefix(prefix + "change.") && now.timeIntervalSince($0.value) < 20 * 3600 }
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
