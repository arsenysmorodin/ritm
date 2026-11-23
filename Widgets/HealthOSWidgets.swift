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
        WidgetCenter.shared.reloadTimelines(ofKind: "RitmWaterWeek")
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
    var nutrition = WidgetStorage.load(HealthWidgetSnapshot.self, file: HealthWidgetSnapshot.file)
    var targets = WidgetTargets.load()
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

/// Each focus has its own WidgetKit identity and supported sizes.
/// All values come from the same local journal or existing HealthKit snapshot.
enum HealthFocus: CaseIterable {
    case resource, daylight, fiber, protein, waterWeek, experiment, sleepGoal, lastMeal
    var kind: String {
        switch self {
        case .resource: "RitmDailyResource"
        case .daylight: "RitmDaylight"
        case .fiber: "RitmFiber"
        case .protein: "RitmProtein"
        case .waterWeek: "RitmWaterWeek"
        case .experiment: "RitmExperiment"
        case .sleepGoal: "RitmSleepGoal"
        case .lastMeal: "RitmLastMeal"
        }
    }
    var title: String {
        switch self {
        case .resource: "Ресурс на день"
        case .daylight: "Дневной свет"
        case .fiber: "Клетчатка"
        case .protein: "Белок"
        case .waterWeek: "Вода · неделя"
        case .experiment: "Эксперимент"
        case .sleepGoal: "Сон · личная цель"
        case .lastMeal: "Последний приём пищи"
        }
    }
    var icon: String {
        switch self {
        case .resource: "bolt.fill"
        case .daylight: "sun.max.fill"
        case .fiber: "carrot.fill"
        case .protein: "fork.knife"
        case .waterWeek: "drop.fill"
        case .experiment: "flask.fill"
        case .sleepGoal: "moon.zzz.fill"
        case .lastMeal: "clock"
        }
    }
    var route: String {
        switch self {
        case .resource: "check-in"
        case .daylight: "daylight"
        case .fiber: "fiber"
        case .protein: "protein"
        case .waterWeek: "water"
        case .experiment: "experiments"
        case .sleepGoal: "sleep"
        case .lastMeal: "meal"
        }
    }
    var header: String {
        switch self {
        case .lastMeal: "Приём пищи"
        case .sleepGoal: "Цель сна"
        default: title
        }
    }
    var description: String {
        switch self {
        case .resource: "Ваша оценка энергии, стресса и сонливости сегодня. Нажмите, чтобы обновить."
        case .daylight: "Минуты дневного света из «Здоровья» и последние семь дней."
        case .fiber, .protein: "Питание из FatSecret через «Здоровье» и ваша личная цель."
        case .waterWeek: "Записанный объём воды за семь дней. Пропуски отмечены отдельно."
        case .experiment: "Текущее условие личного эксперимента."
        case .sleepGoal: "Последняя доступная ночь и ваша цель продолжительности сна."
        case .lastMeal: "Время последней записи о еде из вашего журнала или «Здоровья»."
        }
    }
}

private struct HealthFocusConfiguration {
    let focus: HealthFocus
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: focus.kind, provider: HealthOSProvider()) { entry in
            HealthFocusView(entry: entry, focus: focus)
                .widgetURL(URL(string: "ritm://\(focus.route)"))
                .privacySensitive()
        }
        .configurationDisplayName(focus.title).description(focus.description)
        .supportedFamilies(focus == .waterWeek ? [.systemMedium] : [.systemSmall, .systemMedium])
    }
}

private struct HealthFocusView: View {
    let entry: HealthOSEntry
    let focus: HealthFocus
    @Environment(\.widgetFamily) private var family
    private var palette: WidgetPalette { entry.palette }
    private var events: [HealthEvent] { entry.archive?.events ?? [] }
    private var days: [DailyHealth] { HealthOSLogic.dailyValues(entry.archive?.days ?? [], events: events) }

    var body: some View {
        WidgetCard(palette: palette) {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(title: focus.header, icon: focus.icon, palette: palette)
                WidgetRule(palette: palette)
                Spacer(minLength: 0)
                content
                Spacer(minLength: 0)
            }
        }
    }
    @ViewBuilder private var content: some View {
        switch focus {
        case .resource:
            if let checkIn = HealthOSLogic.events(events, on: entry.date, kind: .checkIn).first,
               let energy = checkIn.ratings["energy"] {
                WidgetNumber(value: "\(energy)", unit: "/ 5 энергии", palette: palette, size: .title)
                WidgetProgressStrip(value: Double(energy), total: 5, palette: palette)
                if family == .systemMedium {
                    Text("Стресс \(checkIn.ratings["stress"].map(String.init) ?? "—")/5 · Сонливость \(checkIn.ratings["sleepiness"].map(String.init) ?? "—")/5")
                        .font(.caption).foregroundStyle(palette.secondary)
                }
                footnote("Ваша оценка · \(time(checkIn.date))")
            } else { empty("Как вы сегодня? Нажмите, чтобы отметить самочувствие.") }
        case .fiber, .protein:
            let nutrient: Nutrient = focus == .fiber ? .fiber : .protein
            if let value = entry.nutrition?.nutrient(nutrient, at: entry.date) {
                WidgetNumber(value: HealthEvent.number(value), unit: "г", palette: palette,
                             size: family == .systemSmall ? .title2 : .largeTitle)
                if let goal = entry.targets.nutrition[nutrient] {
                    WidgetProgressStrip(value: value, total: Double(goal), palette: palette)
                    footnote("Личная цель · \(goal) г")
                }
                footnote("FatSecret → Здоровье")
            } else { empty("Нет записей за сегодня. Откройте «Ритм» для обновления питания.") }
        case .daylight:
            let day = days.last { Calendar.current.isDate($0.date, inSameDayAs: entry.date) }
            if let value = day?.values[.daylightMinutes] {
                WidgetNumber(value: HealthEvent.number(value), unit: "мин сегодня", palette: palette, size: .title)
                weekBars { date in days.first { Calendar.current.isDate($0.date, inSameDayAs: date) }?.values[.daylightMinutes] }
            } else { empty("Минуты дневного света появятся после синхронизации со «Здоровьем».") }
        case .waterWeek:
            let total = HealthOSLogic.total(.water, events: events, day: entry.date)
            HStack(alignment: .firstTextBaseline) {
                WidgetNumber(value: HealthEvent.number(total), unit: "мл сегодня", palette: palette, size: .title)
                Spacer(minLength: 0)
                Text("Цель \(entry.archive?.settings.waterGoal ?? 2000) мл").font(.caption2).foregroundStyle(palette.secondary)
            }
            weekBars { date in
                let logs = HealthOSLogic.events(events, on: date, kind: .water)
                return logs.isEmpty ? nil : logs.reduce(0) { $0 + ($1.amount ?? 0) }
            }
        case .experiment:
            if let experiment = entry.archive?.experiments.first(where: { !$0.finished && $0.assignment(on: entry.date) != nil }),
               let assignment = experiment.assignment(on: entry.date) {
                Text(experiment.title).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                HStack(alignment: .top, spacing: 8) {
                    Text(assignment.isB ? "B" : "A").font(.system(.title2, design: .monospaced, weight: .bold)).foregroundStyle(palette.accent)
                    Text(assignment.isB ? experiment.conditionB : experiment.conditionA)
                        .font(.caption).lineLimit(2).foregroundStyle(palette.secondary)
                }
                if family == .systemMedium && assignment.adaptation { footnote("День адаптации") }
            } else { empty("Нет активного эксперимента. Проверьте одну привычку в «Ритме».") }
        case .sleepGoal:
            if let day = days.last(where: { $0.date <= entry.date && entry.date.timeIntervalSince($0.date) < 3 * 86400 && $0.values[.sleepMinutes] != nil }),
               let minutes = day.values[.sleepMinutes] {
                WidgetNumber(value: "\(Int(minutes) / 60)ч \(Int(minutes) % 60)м", palette: palette, size: .title)
                WidgetProgressStrip(value: minutes, total: Double(entry.targets.sleepMinutes), palette: palette)
                footnote("Цель \(entry.targets.sleepMinutes / 60)ч \(entry.targets.sleepMinutes % 60)м · \(day.date.formatted(.dateTime.day().month(.twoDigits)))")
            } else { empty("Нет недавних записей сна. Обновите данные в «Ритме».") }
        case .lastMeal:
            if let meal = events.filter({ !$0.deleted && $0.kind == .meal && $0.date <= entry.date && entry.date.timeIntervalSince($0.date) < 36 * 3600 }).max(by: { $0.date < $1.date }) {
                WidgetNumber(value: time(meal.date), palette: palette, size: .title)
                Text(meal.title).font(.caption.weight(.medium)).lineLimit(2)
                footnote(Calendar.current.isDate(meal.date, inSameDayAs: entry.date) ? "Последняя запись · сегодня" : meal.date.formatted(.dateTime.day().month(.twoDigits)))
            } else { empty("Нет недавних записей о еде. Нажмите, чтобы добавить приём пищи.") }
        }
    }

    private func empty(_ text: String) -> some View { WidgetEmpty(text: text, palette: palette) }
    private func footnote(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundStyle(palette.secondary).lineLimit(2).minimumScaleFactor(0.8)
    }
    private func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
    private func weekBars(value: (Date) -> Double?) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: entry.date)
        let dates = (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        let values = dates.map(value), maximum = max(values.compactMap { $0 }.max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                VStack(spacing: 3) {
                    VStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(values[index] == nil ? palette.secondary.opacity(0.25) : palette.accent)
                            .frame(height: values[index].map { max(3, $0 / maximum * 28) } ?? 2)
                            .widgetAccentable(values[index] != nil)
                    }.frame(height: 28)
                    Text(values[index] == nil ? "—" : date.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 9)).foregroundStyle(palette.secondary)
                }.frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(date.formatted(.dateTime.day().month())): \(values[index].map { HealthEvent.number($0) } ?? "нет записей") \(focus == .daylight ? "минут" : "миллилитров")")
            }
        }
    }
}

struct DailyResourceWidget: Widget {
    var body: some WidgetConfiguration { HealthFocusConfiguration(focus: .resource).body }
}

struct DaylightWidget: Widget {
    var body: some WidgetConfiguration { HealthFocusConfiguration(focus: .daylight).body }
}

struct FiberWidget: Widget {
    var body: some WidgetConfiguration { HealthFocusConfiguration(focus: .fiber).body }
}

struct ProteinWidget: Widget {
    var body: some WidgetConfiguration { HealthFocusConfiguration(focus: .protein).body }
}

struct WaterWeekWidget: Widget {
    var body: some WidgetConfiguration { HealthFocusConfiguration(focus: .waterWeek).body }
}

struct ExperimentWidget: Widget {
    var body: some WidgetConfiguration { HealthFocusConfiguration(focus: .experiment).body }
}

struct SleepGoalWidget: Widget {
    var body: some WidgetConfiguration { HealthFocusConfiguration(focus: .sleepGoal).body }
}

struct LastMealWidget: Widget {
    var body: some WidgetConfiguration { HealthFocusConfiguration(focus: .lastMeal).body }
}
