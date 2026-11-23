import SwiftUI

/// Explicit simulator-only fixtures; device builds cannot select or seed them.
@MainActor enum HealthOSUITestSupport {
    private static var root: URL? {
        #if DEBUG && targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ritm-ui-testing"), let flag = arguments.firstIndex(of: "--ritm-ui-session"),
              arguments.indices.contains(flag + 1), UUID(uuidString: arguments[flag + 1]) != nil else { return nil }
        return URL.applicationSupportDirectory.appending(path: "RitmUITesting/\(arguments[flag + 1])")
        #else
        return nil
        #endif
    }

    static func journal() -> JournalStore {
        guard let root else { return .live() }
        #if DEBUG && targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        UserDefaults.standard.set(arguments.contains("--ritm-ui-dark") ? "dark" : "light", forKey: RitmAppearance.key)
        #endif
        return JournalStore(url: root.appending(path: "journal.json"))
    }

    static func healthOS() -> HealthOSStore {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ritm-widget-fixtures") {
            let shared = HealthOSStore()
            if shared.events.isEmpty && shared.archive.days.isEmpty && shared.supplements.isEmpty { _ = shared.restore(fixtures()) }
            WidgetStorage.preferences.set("red", forKey: RitmAccent.widgetKey)
        }
        #endif
        guard let root else { return HealthOSStore() }
        let store = HealthOSStore(url: root.appending(path: "health.sqlite"))
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ritm-ui-fixtures"), store.archive.days.isEmpty {
            _ = store.restore(fixtures())
        }
        #endif
        return store
    }

    #if DEBUG && targetEnvironment(simulator)
    private static func fixtures() -> HealthOSArchive {
        let now = Date.now, calendar = Calendar.current, today = calendar.startOfDay(for: now)
        var archive = HealthOSArchive()
        for offset in -90...0 {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let index = offset + 90
            let sleepStart = calendar.date(byAdding: .minute, value: index % 2 == 0 ? -60 : 15, to: day)!
            let end = calendar.date(byAdding: .minute, value: 420 + index % 40, to: sleepStart)!
            let source = "Тестовые данные|simulator.fixture"
            archive.days.append(DailyHealth(date: day, values: [.sleepMinutes: Double(420 + index % 40), .hrv: Double(38 + index % 25),
                .restingPulse: Double(54 + index % 8), .fiber: Double(20 + index % 15), .protein: Double(90 + index % 35),
                .steps: Double(4000 + index % 5 * 1200), .daylightMinutes: Double(20 + index % 45)],
                sources: Dictionary(uniqueKeysWithValues: HealthMeasure.allCases.map { ($0, source) }),
                sleepStart: sleepStart, sleepEnd: end))
            if offset < 0 {
                archive.events.append(.water(Double(1200 + index % 4 * 300), at: day.addingTimeInterval(12 * 3600)))
                archive.events.append(HealthEvent(kind: .caffeine, date: day.addingTimeInterval(Double(index % 2 == 0 ? 10 : 17) * 3600),
                    title: "Тестовый кофе", amount: 80, unit: "мг", source: "Тестовые данные"))
            }
        }
        archive.events.append(.water(600, at: now.addingTimeInterval(-300)))
        let supplement = Supplement(name: "Пример · магний", ingredients: [.init(name: "Магний", amount: 100)],
                                    startsAt: calendar.date(byAdding: .day, value: -3, to: today)!)
        archive.supplements = [supplement]
        let experiment = HealthExperiment(title: "Вечер без экрана", conditionB: "Без экрана за час до сна",
            startsAt: calendar.date(byAdding: .day, value: -12, to: today)!, rule: "Убрать телефон за час до сна")
        archive.experiments = [experiment]
        archive.events.append(HealthEvent(kind: .context, date: now.addingTimeInterval(-200), title: "Тестовые данные симулятора"))
        return archive
    }
    #endif
}

struct HealthOSUITestDisplay: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ritm-ui-large-text") {
            content.dynamicTypeSize(.accessibility3)
        } else { content }
        #else
        content
        #endif
    }
}
