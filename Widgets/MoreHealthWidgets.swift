import Charts
import SwiftUI
import WidgetKit

private struct ActivityEntry: TimelineEntry {
    let date: Date
    let snapshot: ActivityWidgetSnapshot?
    let sleep: TimeInterval?
    let sleepDay: Date
    let palette: WidgetPalette

    var sleepToday: TimeInterval? {
        Calendar.current.startOfDay(for: date) == sleepDay ? sleep : nil
    }
}

private struct ActivityTimeline: TimelineProvider {
    var includeSleep = false

    func placeholder(in context: Context) -> ActivityEntry {
        let now = Date.now
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let steps: [Int?] = [5402, 8321, nil, 4817, 7520, 9238, 6284]
        let energy: [Int?] = [338, 494, nil, 295, 418, 526, 357]
        let days = steps.indices.compactMap { index -> ActivityDay? in
            guard let date = calendar.date(byAdding: .day, value: index - 6, to: today) else { return nil }
            return ActivityDay(date: date, steps: steps[index], activeEnergy: energy[index])
        }
        let samples: [Double] = [74.8, 74.3, 74.7, 74.1, 73.9, 74.2]
        let weights = samples.enumerated().compactMap { index, value -> WeightPoint? in
            guard let date = calendar.date(byAdding: .day, value: index * 5 - 25, to: today) else { return nil }
            return WeightPoint(id: UUID(), date: date, kilograms: value)
        }
        return ActivityEntry(date: now, snapshot: ActivityWidgetSnapshot(days: days, weights: weights),
            sleep: includeSleep ? 7 * 3600 + 43 * 60 : nil, sleepDay: today, palette: WidgetPalette(selection: widgetAccent()))
    }

    func getSnapshot(in context: Context, completion: @escaping (ActivityEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : live())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ActivityEntry>) -> Void) {
        let current = live()
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: current.date))
            ?? current.date.addingTimeInterval(3600)
        let rollover = ActivityEntry(date: midnight, snapshot: current.snapshot, sleep: current.sleep,
                                     sleepDay: current.sleepDay, palette: current.palette)
        completion(Timeline(entries: [current, rollover], policy: .after(min(midnight, current.date.addingTimeInterval(3600)))))
    }

    private func live() -> ActivityEntry {
        let now = Date.now
        let sleep = includeSleep ? WidgetStorage.load(RecoverySnapshot.self, file: RecoverySnapshot.file)?
            .recentDays(1, endingAt: now).first?.sleep?.sleptSeconds : nil
        return ActivityEntry(date: now, snapshot: WidgetStorage.load(ActivityWidgetSnapshot.self, file: ActivityWidgetSnapshot.file),
            sleep: sleep, sleepDay: Calendar.current.startOfDay(for: now), palette: WidgetPalette(selection: widgetAccent()))
    }
}

struct HealthTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ActivityWidgetSnapshot.summaryKind, provider: ActivityTimeline(includeSleep: true)) { entry in
            WidgetCard(palette: entry.palette) { HealthTodayView(entry: entry) }
                .widgetURL(URL(string: "ritm://health"))
        }
        .configurationDisplayName("Здоровье сегодня")
        .description("Шаги, активные калории и длительность сна за текущий день.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct HealthTodayView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ActivityEntry

    var body: some View {
        let day = entry.snapshot?.day(at: entry.date)
        let small = family == .systemSmall
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: "Здоровье сегодня", icon: "cross.case", palette: entry.palette)
            if day?.steps != nil || day?.activeEnergy != nil || entry.sleepToday != nil {
                WidgetRule(palette: entry.palette)
                Spacer(minLength: 0)
                let cells = small ? AnyLayout(VStackLayout(alignment: .leading, spacing: 5))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
                cells {
                    reading("Шаги", value: day?.steps.map(integer), small: small)
                    reading("Активные ккал", value: day?.activeEnergy.map(integer), small: small)
                    reading("Сон", value: entry.sleepToday.map(SleepText.duration), small: small)
                }
                Spacer(minLength: 0)
            } else {
                WidgetEmpty(text: entry.snapshot == nil ? "Подключите Apple «Здоровье» в «Ритме»." : "Сегодня пока нет записей.", palette: entry.palette)
            }
        }
        .privacySensitive()
    }

    private func reading(_ label: String, value: String?, small: Bool) -> some View {
        let layout = small ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 4))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
        return layout {
            Text(label).font(.caption2).foregroundStyle(entry.palette.secondary).lineLimit(1).minimumScaleFactor(0.75)
            if small { Spacer(minLength: 1) }
            WidgetNumber(value: value ?? "—", palette: entry.palette, size: small ? .subheadline : .title2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "Нет данных")
    }
}

struct StepsWidget: Widget {
    var body: some WidgetConfiguration {
        movementConfiguration(kind: ActivityWidgetSnapshot.stepsKind, title: "Шаги", icon: "figure.walk", unit: "шагов",
                              description: "Шаги за сегодня и семь дней.", metric: \.steps)
    }
}

struct ActiveEnergyWidget: Widget {
    var body: some WidgetConfiguration {
        movementConfiguration(kind: ActivityWidgetSnapshot.energyKind, title: "Активная энергия", icon: "flame", unit: "ккал",
                              description: "Активная энергия из Apple «Здоровья» за сегодня и семь дней.", metric: \.activeEnergy)
    }
}

private func movementConfiguration(kind: String, title: String, icon: String, unit: String, description: String,
                                   metric: KeyPath<ActivityDay, Int?>) -> some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: ActivityTimeline()) { entry in
        WidgetCard(palette: entry.palette) {
            MovementWidgetView(entry: entry, title: title, icon: icon, unit: unit, metric: metric)
        }.widgetURL(URL(string: "ritm://health"))
    }
    .configurationDisplayName(title)
    .description(description)
    .supportedFamilies([.systemSmall, .systemMedium])
}

private struct MovementWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ActivityEntry
    let title: String
    let icon: String
    let unit: String
    let metric: KeyPath<ActivityDay, Int?>

    var body: some View {
        let value = entry.snapshot?.day(at: entry.date)?[keyPath: metric]
        let days = entry.snapshot?.week(endingAt: entry.date) ?? []
        let bars = days.map { WeekBar(date: $0.date, value: $0[keyPath: metric].map(Double.init)) }
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: title, icon: icon, palette: entry.palette, context: family == .systemSmall ? nil : "7 дней")
            if bars.contains(where: { $0.value != nil }) {
                WidgetTrendLayout(palette: entry.palette) {
                    VStack(alignment: .leading, spacing: 2) {
                        WidgetNumber(value: value.map(integer) ?? "—", unit: value == nil ? "" : unit, palette: entry.palette)
                        Text(value == nil ? "Сегодня нет данных" : "Сегодня").font(.caption2).foregroundStyle(entry.palette.secondary)
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .accessibilityElement(children: .combine)
                } trend: {
                    WidgetWeekBars(bars: bars, title: title + " за семь дней", palette: entry.palette) { reading in
                        WidgetText.number(reading, fraction: 0) + " " + unit
                    }
                }
            } else {
                WidgetEmpty(text: entry.snapshot == nil ? "Подключите Apple «Здоровье» в «Ритме»." : "За последние семь дней нет записей.",
                            palette: entry.palette)
            }
        }
        .privacySensitive()
    }
}

struct BodyWeightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ActivityWidgetSnapshot.weightKind, provider: ActivityTimeline()) { entry in
            WidgetCard(palette: entry.palette) { BodyWeightView(entry: entry) }
                .widgetURL(URL(string: "ritm://weight"))
        }
        .configurationDisplayName("Вес тела")
        .description("Последнее измерение и график веса за 30 дней.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct BodyWeightView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ActivityEntry

    var body: some View {
        let history = entry.snapshot?.recentWeights(at: entry.date) ?? []
        VStack(alignment: .leading, spacing: 7) {
            WidgetHeader(title: "Вес тела", icon: "scalemass", palette: entry.palette, context: family == .systemSmall ? nil : "30 дней")
            if let last = entry.snapshot?.lastWeight(at: entry.date) {
                WidgetTrendLayout(palette: entry.palette) {
                    VStack(alignment: .leading, spacing: 3) {
                        WidgetNumber(value: WidgetText.number(last.kilograms), unit: "кг", palette: entry.palette)
                        Text(SleepText.shortDate(last.date)).font(.caption2).foregroundStyle(entry.palette.secondary)
                        if let first = history.first, history.count > 1, family != .systemSmall {
                            let difference = last.kilograms - first.kilograms
                            let displayed = abs(difference) < 0.05 ? "0" : (difference > 0 ? "+" : "") + WidgetText.number(difference)
                            Text(displayed + " кг за период").font(.caption2.weight(.medium))
                                .foregroundStyle(entry.palette.secondary).lineLimit(1).minimumScaleFactor(0.75)
                        }
                    }
                    .accessibilityElement(children: .combine)
                } trend: {
                    if history.isEmpty {
                        WidgetEmpty(text: "За 30 дней нет замеров", palette: entry.palette)
                    } else {
                        MetricTrace(points: history.map { TracePoint(date: $0.date, value: $0.kilograms) }, date: entry.date,
                                    days: 30, title: "Вес тела", unit: "кг", palette: entry.palette, connects: true)
                    }
                }
            } else {
                WidgetEmpty(text: "Добавьте измерение веса в Apple «Здоровье».", palette: entry.palette)
            }
        }
        .privacySensitive()
    }
}

struct RestingPulseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RecoverySnapshot.restingPulseKind, provider: RecoveryTimeline()) { entry in
            WidgetCard(palette: entry.palette) { RestingPulseView(entry: entry) }
                .widgetURL(URL(string: "ritm://sleep-vitals"))
        }
        .configurationDisplayName("Пульс в покое")
        .description("Последнее измерение пульса в покое и динамика за семь дней.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct RestingPulseView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecoveryEntry

    var body: some View {
        let days = entry.snapshot?.recentDays(7, endingAt: entry.date) ?? []
        let points = days.compactMap { day in day.readings[.restingPulse].map { TracePoint(date: day.date, value: $0.value) } }
        VStack(alignment: .leading, spacing: 7) {
            WidgetHeader(title: "Пульс в покое", icon: "heart", palette: entry.palette, context: family == .systemSmall ? nil : "7 дней")
            if let latest = points.last {
                WidgetTrendLayout(palette: entry.palette) {
                    VStack(alignment: .leading, spacing: 3) {
                        WidgetNumber(value: WidgetText.number(latest.value, fraction: 0), unit: "уд/мин", palette: entry.palette)
                        Text(SleepText.shortDate(latest.date)).font(.caption2).foregroundStyle(entry.palette.secondary)
                    }
                    .accessibilityElement(children: .combine)
                } trend: {
                    MetricTrace(points: points, date: entry.date, days: 7, title: "Пульс в покое", unit: "уд/мин", palette: entry.palette)
                }
            } else {
                WidgetEmpty(text: "За последние семь дней нет записей пульса в покое.", palette: entry.palette)
            }
        }
        .privacySensitive()
    }
}

struct WeeklySleepDurationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RecoverySnapshot.weeklyDurationKind, provider: RecoveryTimeline()) { entry in
            WidgetCard(palette: entry.palette) { WeeklySleepDurationView(entry: entry) }
                .widgetURL(URL(string: "ritm://sleep"))
        }
        .configurationDisplayName("Длительность сна за неделю")
        .description("Часы сна по дням, средняя длительность и ваша цель сна.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct WeeklySleepDurationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecoveryEntry

    var body: some View {
        let bars = entry.snapshot?.schedule(endingAt: entry.date).days.map {
            WeekBar(date: $0.date, value: $0.sleep?.sleptSeconds)
        } ?? []
        let observed = bars.compactMap(\.value)
        let goal = Double(entry.sleepGoal) * 60
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: "Сон за неделю", icon: "moon.zzz", palette: entry.palette)
            if !observed.isEmpty {
                WidgetTrendLayout(palette: entry.palette) {
                    VStack(alignment: .leading, spacing: 2) {
                        WidgetNumber(value: SleepText.duration(observed.reduce(0, +) / Double(observed.count)),
                                     palette: entry.palette, size: .title)
                        Text("В среднем · \(observed.count) из 7").font(.caption2).foregroundStyle(entry.palette.secondary)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        if family != .systemSmall {
                            Text("Цель " + SleepText.duration(minutes: entry.sleepGoal))
                                .font(.caption2).foregroundStyle(entry.palette.secondary)
                        }
                    }
                } trend: {
                    WidgetWeekBars(bars: bars, title: "Длительность сна за семь дней", palette: entry.palette, goal: goal,
                                   format: SleepText.duration)
                }
            } else {
                WidgetEmpty(text: "За последние семь дней нет записей сна.", palette: entry.palette)
            }
        }
        .privacySensitive()
    }
}

private struct WidgetTrendLayout<Readout: View, Trend: View>: View {
    @Environment(\.widgetFamily) private var family
    let palette: WidgetPalette
    @ViewBuilder let readout: Readout
    @ViewBuilder let trend: Trend

    var body: some View {
        if family == .systemMedium {
            HStack(alignment: .center, spacing: 10) {
                readout.frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(palette.secondary.opacity(0.22)).frame(width: 1)
                    .padding(.vertical, 5).accessibilityHidden(true)
                trend.frame(maxWidth: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                readout
                WidgetRule(palette: palette)
                trend
            }
        }
    }
}

private struct WeekBar: Identifiable {
    var id: Date { date }
    let date: Date
    let value: Double?
}

private struct WidgetWeekBars: View {
    let bars: [WeekBar]
    let title: String
    let palette: WidgetPalette
    var goal: Double? = nil
    let format: (Double) -> String

    var body: some View {
        let limit = max(1, bars.compactMap(\.value).max() ?? 0, goal ?? 0)
        VStack(spacing: 3) {
            GeometryReader { graph in
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(bars) { bar in
                        let isLast = bar.date == bars.last?.date
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2).fill(palette.secondary.opacity(0.09))
                            if let value = bar.value {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(palette.accent.opacity(isLast ? 1 : 0.68))
                                    .frame(height: max(2, graph.size.height * min(value / limit, 1)))
                                    .widgetAccentable()
                            } else {
                                Circle().fill(palette.secondary).frame(width: 3, height: 3).padding(.bottom, 2)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(SleepText.shortDate(bar.date))
                        .accessibilityValue(bar.value.map(format) ?? "Нет записи")
                    }
                }
                .overlay(alignment: .bottom) {
                    if let goal {
                        Rectangle().fill(palette.secondary.opacity(0.65)).frame(height: 1)
                            .offset(y: -max(0, graph.size.height - 1) * min(goal / limit, 1))
                            .accessibilityHidden(true)
                    }
                }
            }
            HStack(spacing: 4) {
                ForEach(bars) { bar in
                    Text(bar.date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "ru_RU"))))
                        .font(.system(size: 8)).foregroundStyle(palette.secondary)
                        .frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.75)
                }
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

private struct TracePoint: Identifiable {
    var id: Date { date }
    let date: Date
    let value: Double
}

private struct MetricTrace: View {
    @Environment(\.widgetFamily) private var family
    let points: [TracePoint]
    let date: Date
    let days: Int
    let title: String
    let unit: String
    let palette: WidgetPalette
    var connects = false

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .day, value: 1 - days, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)
        let lower = points.map(\.value).min() ?? 0
        let upper = points.map(\.value).max() ?? 1
        let padding = max(connects ? 0.3 : 2, (upper - lower) * 0.25)
        Chart(points) { point in
            if connects {
                LineMark(x: .value("Дата", point.date), y: .value(unit, point.value))
                    .foregroundStyle(palette.accent.opacity(0.72))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .accessibilityHidden(true)
            }
            PointMark(x: .value("Дата", point.date), y: .value(unit, point.value))
                .foregroundStyle(palette.accent)
                .symbolSize(point.id == points.last?.id ? 30 : 15)
                .accessibilityLabel(SleepText.shortDate(point.date))
                .accessibilityValue(WidgetText.number(point.value) + " " + unit)
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: max(0, lower - padding)...(upper + padding))
        .chartXAxis {
            if family != .systemSmall {
                AxisMarks(values: [start, today]) { value in
                    if let day = value.as(Date.self) {
                        AxisValueLabel(SleepText.shortDate(day)).font(.caption2).foregroundStyle(palette.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: family == .systemLarge ? 4 : 3)) { _ in
                AxisGridLine().foregroundStyle(palette.secondary.opacity(0.23))
            }
            if family == .systemLarge {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    if let number = value.as(Double.self) {
                        AxisValueLabel(WidgetText.number(number)).font(.caption2).foregroundStyle(palette.secondary)
                    }
                }
            }
        }
        .accessibilityLabel(title + ", \(days) дней")
    }
}

private func integer(_ value: Int) -> String {
    value.formatted(.number.locale(Locale(identifier: "ru_RU")))
}
