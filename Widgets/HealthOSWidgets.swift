import AppIntents
import SwiftUI
import WidgetKit
import UserNotifications

private struct HealthOSActionError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

struct AddWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Добавить воду в Ритм"
    static let isDiscoverable = false
    @Parameter(title: "Миллилитры") var milliliters: Int
    init() { milliliters = 250 }
    init(_ value: Int) { milliliters = value }
    func perform() async throws -> some IntentResult {
        guard (10...5000).contains(milliliters) else { throw HealthOSActionError("Проверьте порцию воды.") }
        let database = try HealthDatabase(url: HealthDatabase.sharedURL())
        try database.save(.water(Double(milliliters)))
        WidgetCenter.shared.reloadTimelines(ofKind: "RitmWater")
        WidgetCenter.shared.reloadTimelines(ofKind: "RitmDayTimeline")
        return .result()
    }
}

struct TakeSupplementIntent: AppIntent {
    static let title: LocalizedStringResource = "Отметить приём добавки"
    static let isDiscoverable = false
    @Parameter(title: "Продукт") var supplementID: String
    @Parameter(title: "Время по плану") var slotTimestamp: Double
    init() { supplementID = ""; slotTimestamp = 0 }
    init(_ id: UUID, slot: Date) { supplementID = id.uuidString; slotTimestamp = slot.timeIntervalSince1970 }
    func perform() async throws -> some IntentResult {
        let database = try HealthDatabase(url: HealthDatabase.sharedURL())
        let archive = try database.archive(), slot = Date(timeIntervalSince1970: slotTimestamp)
        guard let supplement = archive.supplements.first(where: { $0.id.uuidString == supplementID }),
              Calendar.current.isDateInToday(slot), supplement.slots(on: slot).contains(slot) else {
            throw HealthOSActionError("Расписание изменилось. Откройте «Ритм».")
        }
        _ = try database.take(supplement, at: slot)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["ritm.health.supplement.\(supplement.id).\(Int(slot.timeIntervalSince1970))"])
        WidgetCenter.shared.reloadTimelines(ofKind: "RitmSupplements")
        WidgetCenter.shared.reloadTimelines(ofKind: "RitmDayTimeline")
        return .result()
    }
}

private struct HealthOSEntry: TimelineEntry {
    let date: Date
    let archive: HealthOSArchive?
    let palette = WidgetPalette(selection: widgetAccent())
}

private struct HealthOSProvider: TimelineProvider {
    func placeholder(in context: Context) -> HealthOSEntry { .init(date: .now, archive: HealthOSArchive()) }
    func getSnapshot(in context: Context, completion: @escaping (HealthOSEntry) -> Void) {
        completion(.init(date: .now, archive: read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HealthOSEntry>) -> Void) {
        let now = Date.now
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86400)
        let nextMidnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? midnight
        let archive = read()
        completion(Timeline(entries: [.init(date: now, archive: archive), .init(date: nextMidnight, archive: archive)],
                            policy: .after(now.addingTimeInterval(15 * 60))))
    }
    private func read() -> HealthOSArchive? { try? HealthDatabase(url: HealthDatabase.sharedURL()).archive() }
}

struct WaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RitmWater", provider: HealthOSProvider()) { entry in WaterWidgetView(entry: entry) }
            .configurationDisplayName("Вода").description("Дневная цель и быстрые порции. Запись в «Здоровье» синхронизируется при открытии приложения.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct WaterWidgetView: View {
    let entry: HealthOSEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        let palette = entry.palette
        WidgetCard(palette: palette) {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 6) {
                WidgetHeader(title: "Вода", icon: "drop.fill", palette: palette, context: "Сегодня")
                WidgetRule(palette: palette)
                if let archive = entry.archive {
                    let total = HealthOSLogic.total(.water, events: archive.events, day: entry.date)
                    if family == .systemSmall {
                        value(total, goal: archive.settings.waterGoal, size: .title2)
                        WidgetProgressStrip(value: total, total: Double(archive.settings.waterGoal), palette: palette)
                        Spacer(minLength: 0)
                        controls(archive, compact: true)
                    } else {
                        Spacer(minLength: 0)
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                value(total, goal: archive.settings.waterGoal, size: .largeTitle)
                                WidgetProgressStrip(value: total, total: Double(archive.settings.waterGoal), palette: palette)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            controls(archive, compact: false).frame(maxWidth: .infinity)
                        }
                        Spacer(minLength: 0)
                    }
                } else { WidgetEmpty(text: "Откройте «Ритм» для настройки воды.", palette: palette) }
            }.privacySensitive()
        }.widgetURL(URL(string: "ritm://water"))
    }
    private func value(_ total: Double, goal: Int, size: Font.TextStyle) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetNumber(value: WidgetText.number(total, fraction: 0), unit: "мл", palette: entry.palette, size: size)
            Text("из \(goal) мл").font(.caption2).foregroundStyle(entry.palette.secondary)
        }
    }
    private func controls(_ archive: HealthOSArchive, compact: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(archive.settings.waterPortions.prefix(compact ? 1 : 3).enumerated()), id: \.offset) { _, amount in
                Button(intent: AddWaterIntent(amount)) {
                    VStack(spacing: 1) {
                        Text("+\(amount)").font(.caption.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                        if !compact { Text("мл").font(.caption2) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(entry.palette.accent)
                    .background(entry.palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).accessibilityLabel("Добавить \(amount) миллилитров воды")
            }
        }
    }
}

struct SupplementsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RitmSupplements", provider: HealthOSProvider()) { entry in
            let palette = entry.palette
            WidgetCard(palette: palette) {
                VStack(alignment: .leading, spacing: 4) {
                    WidgetHeader(title: "Добавки", icon: "pills", palette: palette, context: "Сегодня")
                    WidgetRule(palette: palette)
                    if let archive = entry.archive {
                        let slots = archive.supplements.flatMap { supplement in supplement.slots(on: entry.date).map { (supplement, $0) } }.sorted { $0.1 < $1.1 }
                        let remaining = slots.filter { !HealthOSLogic.completedSlot($0.1, supplement: $0.0.id, events: archive.events) }
                        if let next = remaining.first {
                            Text(next.0.name).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                            Text("\(next.1.formatted(date: .omitted, time: .shortened)) · \(HealthEvent.number(next.0.servings)) порц.")
                                .font(.caption).foregroundStyle(palette.secondary)
                            Spacer(minLength: 0)
                            Button(intent: TakeSupplementIntent(next.0.id, slot: next.1)) {
                                Label("Принято", systemImage: "checkmark").font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(palette.accent)
                                    .background(palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        } else {
                            WidgetEmpty(text: slots.isEmpty ? "Добавьте продукты и расписание в «Ритме»." : "Все приёмы на сегодня отмечены.", palette: palette)
                        }
                    } else { WidgetEmpty(text: "Откройте «Ритм» для настройки добавок.", palette: palette) }
                }.privacySensitive()
            }.widgetURL(URL(string: "ritm://supplements"))
        }.configurationDisplayName("Добавки").description("Ближайший приём и отметка одним касанием.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CaffeineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RitmCaffeine", provider: HealthOSProvider()) { entry in
            let palette = entry.palette
            WidgetCard(palette: palette) {
                VStack(alignment: .leading, spacing: 9) {
                    WidgetHeader(title: "Кофеин", icon: "cup.and.saucer", palette: palette, context: "Сегодня")
                    WidgetRule(palette: palette)
                    if let archive = entry.archive {
                        let events = HealthOSLogic.events(archive.events, on: entry.date, kind: .caffeine)
                        if let last = events.first {
                            Spacer(minLength: 0)
                            WidgetNumber(value: WidgetText.number(events.reduce(0) { $0 + ($1.amount ?? 0) }, fraction: 0), unit: "мг", palette: palette)
                            Spacer(minLength: 0)
                            Text("Последний приём \(last.date.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(palette.secondary)
                        } else { WidgetEmpty(text: "Нет записей. Нажмите, чтобы отметить кофеин.", palette: palette) }
                    } else { WidgetEmpty(text: "Откройте «Ритм».", palette: palette) }
                }.privacySensitive()
            }.widgetURL(URL(string: "ritm://caffeine"))
        }.configurationDisplayName("Кофеин").description("Количество и время последнего приёма без оценки остаточного кофеина.")
            .supportedFamilies([.systemSmall])
    }
}

struct DayTimelineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RitmDayTimeline", provider: HealthOSProvider()) { entry in
            let palette = entry.palette
            WidgetCard(palette: palette) {
                VStack(alignment: .leading, spacing: 10) {
                    WidgetHeader(title: "Лента дня", icon: "clock", palette: palette)
                    WidgetRule(palette: palette)
                    if let archive = entry.archive {
                        let events = HealthOSLogic.events(archive.events, on: entry.date)
                        if events.isEmpty { WidgetEmpty(text: "Вода, добавки, питание и ощущения в одном журнале.", palette: palette) }
                        ForEach(events.prefix(3)) { event in
                            HStack(spacing: 10) {
                                Text(event.date, style: .time).font(.caption2).monospacedDigit().foregroundStyle(palette.secondary)
                                Text(event.title).font(.caption.weight(.medium)).lineLimit(1)
                                Spacer(minLength: 0)
                                Text(event.summary).font(.caption2).foregroundStyle(palette.secondary).lineLimit(1)
                            }.privacySensitive()
                        }
                        Spacer(minLength: 0)
                    } else { WidgetEmpty(text: "Откройте «Ритм».", palette: palette) }
                }.privacySensitive()
            }.widgetURL(URL(string: "ritm://timeline"))
        }.configurationDisplayName("Лента дня").description("Последние записи вашего Health OS.").supportedFamilies([.systemMedium])
    }
}
