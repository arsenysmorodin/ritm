import Charts
import SwiftUI
import WidgetKit

private struct HealthEntry: TimelineEntry {
    let date: Date
    let snapshot: HealthWidgetSnapshot?
    let accent: RitmAccent
    var targets = WidgetTargets.load()
    var palette: WidgetPalette { WidgetPalette(selection: accent) }

    static func live(at date: Date = .now) -> HealthEntry {
        HealthEntry(date: date,
                    snapshot: WidgetStorage.load(HealthWidgetSnapshot.self, file: HealthWidgetSnapshot.file),
                    accent: widgetAccent())
    }
}

private struct HealthTimeline: TimelineProvider {
    func placeholder(in context: Context) -> HealthEntry {
        let now = Date.now
        let start = Calendar.current.startOfDay(for: now)
        let interval = now.timeIntervalSince(start)
        func series(_ values: [Double]) -> CardiacSeries {
            let points = values.enumerated().map { index, value in
                CardiacReading(date: start.addingTimeInterval(interval * Double(index + 1) / Double(values.count)), value: value)
            }
            return CardiacSeries(points, from: start, through: now)
        }
        return HealthEntry(date: now,
                           snapshot: HealthWidgetSnapshot(day: start, pulse: series([60, 71, 65, 78, 68]),
                                                          hrv: series([34, 39, 46, 43, 51]),
                                                          nutrition: [.energy: 1710, .protein: 94, .fat: 56, .carbs: 211,
                                                                      .fiber: 23, .sugar: 38, .saturatedFat: 16, .sodium: 1564]),
                           accent: widgetAccent())
    }

    func getSnapshot(in context: Context, completion: @escaping (HealthEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : .live())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HealthEntry>) -> Void) {
        let current = HealthEntry.live()
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: current.date))
            ?? current.date.addingTimeInterval(3600)
        let rollover = HealthEntry(date: midnight, snapshot: current.snapshot, accent: current.accent, targets: current.targets)
        completion(Timeline(entries: [current, rollover], policy: .after(min(midnight, current.date.addingTimeInterval(3600)))))
    }
}

struct HeartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HealthWidgetSnapshot.heartKind, provider: HealthTimeline()) { entry in
            WidgetCard(palette: entry.palette) { HeartWidgetView(entry: entry) }
                .widgetURL(URL(string: "ritm://health"))
        }
        .configurationDisplayName("Пульс и ВСР")
        .description("Последние измерения пульса и ВСР, график ВСР за сегодня.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct HeartWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HealthEntry

    private var compact: Bool { family == .systemSmall }
    private var expanded: Bool { family == .systemLarge }
    private var palette: WidgetPalette { entry.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 12 : 6) {
            WidgetHeader(title: "Пульс и ВСР", icon: "waveform.path.ecg", palette: palette)
            if let snapshot = entry.snapshot {
                readings(snapshot)
                if compact {
                    Spacer(minLength: 0)
                } else {
                    WidgetRule(palette: palette)
                    let points = snapshot.isToday(entry.date) ? snapshot.hrv.today : []
                    if points.isEmpty {
                        WidgetEmpty(text: "Нет замеров ВСР за сегодня", palette: palette)
                    } else {
                        variabilityChart(points)
                    }
                }
            } else {
                WidgetEmpty(text: "Подключите Apple «Здоровье» в «Ритме».", palette: palette)
            }
        }
        .privacySensitive()
    }

    private func readings(_ snapshot: HealthWidgetSnapshot) -> some View {
        let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 5))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            measurement("ВСР (SDNN)", unit: "мс", reading: snapshot.hrv.recent(at: entry.date))
            measurement("Пульс", unit: "уд/мин", reading: snapshot.pulse.recent(at: entry.date))
        }
    }

    private func measurement(_ title: String, unit: String, reading: CardiacReading?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(palette.secondary)
            if let reading {
                WidgetNumber(value: WidgetText.number(reading.value), unit: unit, palette: palette, size: expanded ? .title2 : .headline)
                Text(timeOf(reading.date))
                    .font(.caption2).foregroundStyle(palette.secondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            } else {
                Text("Нет замеров").font(.caption.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func timeOf(_ date: Date) -> String {
        let locale = Locale(identifier: "ru_RU")
        return Calendar.current.isDate(date, inSameDayAs: entry.date)
            ? date.formatted(.dateTime.hour().minute().locale(locale))
            : date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale))
    }

    private func variabilityChart(_ points: [CardiacReading]) -> some View {
        let start = Calendar.current.startOfDay(for: entry.date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        let low = points.map(\.value).min() ?? 0
        let high = points.map(\.value).max() ?? 1
        let padding = max(3, (high - low) / 8)
        let ticks = high - low < 5 ? [low] : expanded ? [low, low + (high - low) / 2, high] : [low, high]
        return Chart(points) { point in
            LineMark(x: .value("Время", point.date), y: .value("ВСР, мс", point.value))
                .foregroundStyle(palette.accent)
                .lineStyle(StrokeStyle(lineWidth: expanded ? 2.5 : 2, lineCap: .round, lineJoin: .round))
            if expanded || point.id == points.last?.id {
                PointMark(x: .value("Время", point.date), y: .value("ВСР, мс", point.value))
                    .foregroundStyle(palette.accent).symbolSize(20)
            }
        }
        .chartYScale(domain: max(0, low - padding)...(high + padding))
        .chartXScale(domain: start...end)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                if let date = value.as(Date.self), date < end {
                    AxisValueLabel(collisionResolution: .greedy) {
                        Text(date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "ru_RU"))))
                            .font(.caption2).foregroundStyle(palette.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: ticks) { _ in
                AxisGridLine().foregroundStyle(palette.secondary.opacity(0.24))
            }
            AxisMarks(position: .leading, values: ticks) { value in
                if let value = value.as(Double.self) {
                    AxisValueLabel {
                        Text(WidgetText.number(value)).font(.caption2).foregroundStyle(palette.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Вариабельность сердечного ритма за сегодня")
    }
}

struct NutritionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HealthWidgetSnapshot.nutritionKind, provider: HealthTimeline()) { entry in
            WidgetCard(palette: entry.palette) { NutritionWidgetView(entry: entry) }
                .widgetURL(URL(string: "ritm://health"))
        }
        .configurationDisplayName("Питание FatSecret")
        .description("Калории, белки, жиры, углеводы и клетчатка из FatSecret через Apple «Здоровье».")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct NutritionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HealthEntry
    private var palette: WidgetPalette { entry.palette }

    var body: some View {
        let small = family == .systemSmall
        let full = family == .systemLarge
        let hasData = entry.snapshot?.isToday(entry.date) == true && entry.snapshot?.nutrition.isEmpty == false
        VStack(alignment: .leading, spacing: small ? 4 : (full ? 12 : 6)) {
            WidgetHeader(title: "Питание", icon: "fork.knife", palette: palette, context: small ? nil : "FatSecret")
            if let energy = amount(.energy) {
                WidgetNumber(value: WidgetText.number(energy, fraction: 0), unit: goalLabel(.energy) ?? "ккал", palette: palette,
                             size: small ? .title2 : .largeTitle)
                if !small, let goal = entry.targets.nutrition[.energy] {
                    WidgetProgressStrip(value: energy, total: Double(goal), palette: palette)
                } else {
                    WidgetRule(palette: palette)
                }
            } else {
                Text("Калории: нет данных").font(.caption).foregroundStyle(palette.secondary)
            }
            if !hasData && !small {
                Text(entry.snapshot == nil ? "Подключите «Здоровье» в «Ритме»." : "Нет записей FatSecret за сегодня.")
                    .font(.caption).foregroundStyle(palette.secondary)
            }
            let core: [Nutrient] = [.protein, .fat, .carbs, .fiber]
            let items = full ? core + [.sugar, .saturatedFat, .sodium] : core
            let columns = Array(repeating: GridItem(.flexible(), spacing: 5, alignment: .leading), count: small || full ? 2 : 4)
            LazyVGrid(columns: columns, alignment: .leading, spacing: small ? 3 : 10) {
                ForEach(items, id: \.self) { item in nutrient(item) }
            }
            Spacer(minLength: 0)
        }
        .privacySensitive()
    }

    private func amount(_ nutrient: Nutrient) -> Double? {
        entry.snapshot?.nutrient(nutrient, at: entry.date)
    }

    private func goalLabel(_ nutrient: Nutrient) -> String? {
        entry.targets.nutrition[nutrient].map { "из \(WidgetText.number(Double($0), fraction: 0)) \(nutrient.unit)" }
    }

    private func nutrient(_ kind: Nutrient) -> some View {
        let wide = family == .systemLarge
        let value = amount(kind)
        let goal = entry.targets.nutrition[kind]
        let current = value.map { "\(WidgetText.number($0)) " + (goalLabel(kind) ?? kind.unit) }
        return VStack(alignment: .leading, spacing: 1) {
            Text(kind.title).font(wide ? .subheadline : .caption2)
                .foregroundStyle(kind == .fiber ? palette.accent : palette.secondary)
                .lineLimit(1).minimumScaleFactor(0.74)
            Text(current ?? (kind == .fiber ? "Нет данных" : "—"))
                .font((wide ? Font.headline : .caption).weight(.semibold)).monospacedDigit()
                .foregroundStyle(kind == .fiber && value != nil ? palette.accent : palette.primary)
                .lineLimit(1).minimumScaleFactor(0.75)
            if wide, let goal, let value {
                WidgetProgressStrip(value: value, total: Double(goal), palette: palette)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.title)
        .accessibilityValue(current ?? "Нет данных")
    }
}
