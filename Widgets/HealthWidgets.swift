import Charts
import SwiftUI
import WidgetKit

private struct HealthEntry: TimelineEntry {
    let date: Date
    let snapshot: HealthWidgetSnapshot?
    let accent: RitmAccent
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
        let rollover = HealthEntry(date: midnight, snapshot: current.snapshot, accent: current.accent)
        completion(Timeline(entries: [current, rollover], policy: .after(min(midnight, current.date.addingTimeInterval(3600)))))
    }
}

struct HeartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HealthWidgetSnapshot.heartKind, provider: HealthTimeline()) { entry in
            HeartWidgetView(entry: entry)
                .containerBackground(entry.palette.surface, for: .widget)
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
            Label("Пульс и ВСР", systemImage: "waveform.path.ecg")
                .font(.subheadline.weight(.semibold)).foregroundStyle(palette.accent)
                .widgetAccentable()
            if let snapshot = entry.snapshot {
                readings(snapshot)
                if compact {
                    Spacer(minLength: 0)
                } else {
                    let points = snapshot.isToday(entry.date) ? snapshot.hrv.today : []
                    if points.isEmpty {
                        Text("Нет замеров ВСР за сегодня")
                            .font(.caption)
                            .foregroundStyle(palette.secondary)
                            .frame(maxHeight: .infinity, alignment: .center)
                    } else {
                        variabilityChart(points)
                    }
                }
            } else {
                Spacer(minLength: 0)
                Text("Подключите Apple «Здоровье» в «Ритме».")
                    .font(.caption).foregroundStyle(palette.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(palette.primary)
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
                Text("\(format(reading.value)) \(unit)")
                    .font((expanded ? Font.title2 : .headline).weight(.semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.73)
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
            AxisMarks(position: .leading, values: .automatic(desiredCount: expanded ? 5 : 3)) { value in
                if let value = value.as(Double.self) {
                    AxisValueLabel(format(value)).font(.caption2).foregroundStyle(palette.secondary)
                }
                AxisGridLine().foregroundStyle(palette.secondary.opacity(0.24))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Вариабельность сердечного ритма за сегодня")
    }
}

struct NutritionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HealthWidgetSnapshot.nutritionKind, provider: HealthTimeline()) { entry in
            NutritionWidgetView(entry: entry)
                .containerBackground(entry.palette.surface, for: .widget)
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
        VStack(alignment: .leading, spacing: small ? 5 : 9) {
            HStack(alignment: .firstTextBaseline) {
                Label("Питание", systemImage: "fork.knife")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(palette.accent).widgetAccentable()
                if !small {
                    Spacer(minLength: 4)
                    Text("Сегодня · FatSecret").font(.caption).foregroundStyle(palette.secondary)
                }
            }
            if let energy = amount(.energy) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(format(energy, fraction: false)).font((small ? Font.title2 : .largeTitle).weight(.semibold)).monospacedDigit()
                    Text("ккал").font(.caption).foregroundStyle(palette.secondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("Калории: нет данных").font(.caption).foregroundStyle(palette.secondary)
            }
            if !hasData && !small {
                Text(entry.snapshot == nil ? "Подключите «Здоровье» в «Ритме»." : "Нет записей FatSecret за сегодня.")
                    .font(.caption).foregroundStyle(palette.secondary)
            }
            Spacer(minLength: 0)
            let core: [Nutrient] = [.protein, .fat, .carbs, .fiber]
            let items = full ? core + [.sugar, .saturatedFat, .sodium] : core
            let columns = Array(repeating: GridItem(.flexible(), spacing: 5, alignment: .leading), count: small || full ? 2 : 4)
            LazyVGrid(columns: columns, alignment: .leading, spacing: small ? 4 : 10) {
                ForEach(items, id: \.self) { item in nutrient(item) }
            }
        }
        .foregroundStyle(palette.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .privacySensitive()
    }

    private func amount(_ nutrient: Nutrient) -> Double? {
        entry.snapshot?.nutrient(nutrient, at: entry.date)
    }

    private func nutrient(_ kind: Nutrient) -> some View {
        let wide = family == .systemLarge
        let value = amount(kind)
        return VStack(alignment: .leading, spacing: 1) {
            Text(kind.title).font(wide ? .subheadline : .caption2)
                .foregroundStyle(kind == .fiber ? palette.accent : palette.secondary)
                .lineLimit(1).minimumScaleFactor(0.74)
            Text(value.map { "\(format($0)) \(kind.unit)" } ?? (kind == .fiber ? "Нет данных" : "—"))
                .font((wide ? Font.headline : .caption).weight(.semibold)).monospacedDigit()
                .foregroundStyle(kind == .fiber && value != nil ? palette.accent : palette.primary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.title)
        .accessibilityValue(value.map { "\(format($0)) \(kind.unit)" } ?? "Нет данных")
    }
}

private func format(_ number: Double, fraction: Bool = true) -> String {
    number.formatted(.number.precision(.fractionLength(0...(fraction ? 1 : 0))).locale(Locale(identifier: "ru_RU")))
}
