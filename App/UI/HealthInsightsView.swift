import SwiftUI
import Charts

struct HealthInsightsView: View {
    let store: HealthOSStore
    let journal: JournalStore
    @State private var metric = HealthMeasure.sleepMinutes
    @State private var period = 28
    @State private var exposure = HealthExposure.lateCaffeine
    @State private var supplementID: UUID?
    @State private var outcome = HealthMeasure.sleepMinutes
    var body: some View {
        Page {
            Text("Динамика").font(Theme.screenTitle).fontWidth(.expanded).accessibilityAddTraits(.isHeader)
            Text("Пустые дни остаются пропусками. Ночные показатели относятся к утру окончания сна.")
                .font(.subheadline).foregroundStyle(Theme.secondary)
            NavigationLink { ExperimentsView(store: store) } label: {
                HealthRouteRow(title: "Эксперименты", subtitle: "Привычки, самочувствие и работоспособность", icon: "flask")
            }.buttonStyle(PressStyle()).accessibilityIdentifier("dynamics.experiments")
            NavigationLink { WeeklyHealthReport(store: store) } label: {
                HealthRouteRow(title: "Неделя в цифрах", subtitle: "Сравнение с предыдущей неделей", icon: "calendar")
            }.buttonStyle(PressStyle())
            Panel {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeading(title: "Сравнить периоды")
                    Picker("Показатель", selection: $metric) { ForEach(HealthMeasure.allCases) { Text($0.title).tag($0) } }
                    Picker("Длина периода", selection: $period) {
                        Text("7 дней").tag(7); Text("28 дней").tag(28); Text("90 дней").tag(90)
                    }.pickerStyle(.segmented)
                    ComparisonPanel(result: HealthAnalytics.comparePeriods(metric: metric, days: store.days, length: period),
                                    metric: metric, labelA: "Предыдущие \(period) дн.", labelB: "Последние \(period) дн.")
                }
            }
            Panel {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeading(title: "Проверить связь")
                    Picker("Привычка", selection: $exposure) { ForEach(HealthExposure.allCases) { Text($0.title).tag($0) } }
                    Picker("Исход", selection: $outcome) { ForEach(HealthMeasure.outcomes) { Text($0.title).tag($0) } }
                    if exposure == .supplement {
                        Picker("Добавка", selection: $supplementID) {
                            Text("Выберите продукт").tag(Optional<UUID>.none)
                            ForEach(store.archive.supplements) { Text($0.name).tag(Optional($0.id)) }
                        }
                        Text("Сравниваются дни с явной отметкой «принято» и «пропущено» для выбранного продукта. Пропуск дневника не означает отсутствие приёма.").font(.caption).foregroundStyle(Theme.secondary)
                    }
                    Text("Для сна, ВСР и пульса в покое учитывается предшествующий день. Порог разделения групп — условие сравнения, а не рекомендация.")
                        .font(.caption).foregroundStyle(Theme.secondary)
                    let result = HealthAnalytics.pattern(exposure: exposure, outcome: outcome, days: store.days, events: store.events, workouts: journal.journal.records,
                        waterGoal: store.settings.waterGoal, supplementID: supplementID)
                    ComparisonPanel(result: result, metric: outcome, labelA: "Без условия", labelB: "С условием")
                    if let validation = result.validationDelta {
                        Text("Поздние 30% наблюдений: разница \(signed(validation)) \(outcome.unit). Это отдельная проверка на более новых днях.")
                            .font(.subheadline)
                    } else {
                        Text("Для проверки на более новых днях нужно хотя бы по 4 наблюдения в каждой группе в последних 30% истории.")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                    Text("Исследовательское сравнение первых 70% наблюдений. Связь не доказывает причину: время, стресс, питание и тренировки могут меняться вместе. Дни без записей привычки не считаются днями без неё. Временной тренд не скорректирован.")
                        .font(.caption).foregroundStyle(Theme.secondary)
                    if result.contextDays > 0 { Text("В выборке \(result.contextDays) дн. с отмеченными событиями режима.").font(.caption).foregroundStyle(Theme.secondary) }
                    if let steps = result.stepsDifference { Text("Активность групп также различается в среднем на \(signed(steps)) шагов.").font(.caption).foregroundStyle(Theme.secondary) }
                }
            }
            SectionHeading(title: "Показатели")
            ForEach(HealthMeasure.allCases) { item in
                NavigationLink { HealthMetricDetail(store: store, metric: item) } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.title).font(.subheadline)
                        Spacer()
                        if let value = store.days.last(where: { $0.values[item] != nil })?.values[item] {
                            Text("\(HealthEvent.number(value)) \(item.unit)").monospacedDigit().font(.subheadline.weight(.semibold))
                        } else { Text("Нет данных").font(.caption).foregroundStyle(Theme.secondary) }
                        Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
                    }.frame(minHeight: 48).foregroundStyle(Theme.primary)
                }.buttonStyle(PressStyle())
            }
            NavigationLink { ManualMeasurementsView(store: store) } label: {
                HealthRouteRow(title: "Свои измерения", subtitle: "Талия, давление, анализы и заметки", icon: "waveform.path.ecg")
            }.buttonStyle(PressStyle())
        }.navigationTitle("Динамика").navigationBarTitleDisplayMode(.inline)
    }
}

struct ComparisonPanel: View {
    let result: HealthComparison
    let metric: HealthMeasure
    var labelA = "A"
    var labelB = "B"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) { values }
                VStack(alignment: .leading, spacing: 12) { values }
            }
            if let delta = result.delta, result.a.count >= 3, result.b.count >= 3 {
                Text("Разница: \(signed(delta)) \(metric.unit)").font(Theme.number)
            } else { Text("Для сравнения нужно хотя бы по 3 дня в каждой группе.").font(.subheadline).foregroundStyle(Theme.secondary) }
            if let interval = result.interval {
                Text("Описательный 95% интервал: \(signed(interval.lowerBound))…\(signed(interval.upperBound)) \(metric.unit). Перевыборка календарными неделями, 800 повторов.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            } else { Text("Недостаточно недель для оценки неопределённости блоками.").font(.caption).foregroundStyle(Theme.secondary) }
            if !result.source.isEmpty { Text("Источник: \(sourceName(result.source))").font(.caption).foregroundStyle(Theme.secondary) }
            if result.excludedSources > 0 { Text("Исключены дни с другим источником: \(result.excludedSources).").font(.caption).foregroundStyle(Theme.secondary) }
        }
    }
    @ViewBuilder private var values: some View {
        comparisonValue(labelA, mean: result.meanA, count: result.a.count)
        comparisonValue(labelB, mean: result.meanB, count: result.b.count)
    }
    private func comparisonValue(_ title: String, mean: Double?, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Theme.secondary)
            Text(mean.map { "\(HealthEvent.number($0)) \(metric.unit)" } ?? "—").font(Theme.number)
            Text("\(count) дн. с данными").font(.caption).foregroundStyle(Theme.secondary)
        }.accessibilityElement(children: .combine)
    }
}

struct HealthMetricDetail: View {
    let store: HealthOSStore
    let metric: HealthMeasure
    @State private var period = 90
    @State private var selectedSource = ""
    @Environment(\.ritmAccent) private var accent
    private var history: [DailyHealth] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -period, to: .now) ?? .distantPast
        return store.days.filter { $0.date >= cutoff && $0.values[metric] != nil && (selectedSource.isEmpty || $0.sources[metric] == selectedSource) }
    }
    var body: some View {
        Page {
            Picker("Период истории", selection: $period) {
                Text("30 дн.").tag(30); Text("90 дн.").tag(90); Text("Год").tag(365); Text("Всё").tag(36500)
            }.pickerStyle(.segmented)
            let sources = Array(Set(store.days.compactMap { $0.sources[metric] })).sorted()
            if sources.count > 1 {
                Picker("Источник", selection: $selectedSource) {
                    Text("Все источники").tag("")
                    ForEach(sources, id: \.self) { Text(sourceName($0)).tag($0) }
                }
            }
            if history.isEmpty {
                HintPanel(icon: "chart.xyaxis.line", title: "Нет наблюдений", text: "Записывайте привычки или разрешите чтение показателя из «Здоровья». Отсутствие данных не означает нулевое значение.")
            } else {
                let values = history.compactMap { $0.values[metric] }.sorted()
                MetricValue(title: "Последнее · \(Format.date(history.last!.date))", value: "\(HealthEvent.number(history.last!.values[metric]!)) \(metric.unit)", prominence: true)
                Text("Наблюдений: \(values.count) дн. Личный диапазон 10–90%: \(HealthEvent.number(values[Int(Double(values.count - 1) * 0.1)]))…\(HealthEvent.number(values[Int(Double(values.count - 1) * 0.9)])) \(metric.unit). Это описательная статистика, не медицинская норма.")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
                if ![.restingPulse, .sleepingPulse].contains(metric) {
                    Chart(history) { day in
                        if let value = day.values[metric] {
                            if metric == .sleepMinutes || metric == .steps || metric == .daylightMinutes {
                                BarMark(x: .value("День", day.date, unit: .day), y: .value(metric.title, value)).foregroundStyle(accent)
                            } else {
                                PointMark(x: .value("День", day.date), y: .value(metric.title, value)).foregroundStyle(accent)
                            }
                        }
                    }.chartYAxisLabel(metric.unit).frame(height: 220)
                        .accessibilityLabel("История \(metric.title), \(history.count) дней. Точные значения перечислены ниже.")
                }
                ForEach(history.reversed().prefix(90)) { day in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(day.date, format: .dateTime.day().month(.abbreviated).year())
                            Spacer()
                            Text("\(HealthEvent.number(day.values[metric]!)) \(metric.unit)").fontWeight(.semibold).monospacedDigit()
                        }.font(.subheadline)
                        Text(sourceName(day.sources[metric] ?? "Ритм") + (day.counts[metric].map { " · \($0) записей" } ?? " · дневной итог"))
                            .font(.caption).foregroundStyle(Theme.secondary)
                        let events = HealthOSLogic.events(store.events, on: day.date).filter { $0.kind == .context }
                        ForEach(events) { Text($0.title).font(.caption).foregroundStyle(accent) }
                    }.accessibilityElement(children: .combine)
                }
                if history.count > 90 { Text("В списке последние 90 дней. График и диапазон учитывают весь выбранный период.").font(.caption).foregroundStyle(Theme.secondary) }
            }
        }.navigationTitle(metric.title).navigationBarTitleDisplayMode(.inline)
    }
}

struct WeeklyHealthReport: View {
    let store: HealthOSStore
    var body: some View {
        Page {
            Text("Последние 7 полных дней").font(Theme.sectionTitle)
            ForEach([HealthMeasure.sleepMinutes, .hrv, .restingPulse, .steps, .water, .caffeine, .fiber, .daylightMinutes]) { metric in
                Panel {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeading(title: metric.title)
                        ComparisonPanel(result: HealthAnalytics.comparePeriods(metric: metric, days: store.days, length: 7), metric: metric, labelA: "Неделей раньше", labelB: "Последняя неделя")
                    }
                }
            }
            Text("Сводка использует доступные наблюдения. Неполные дневники питания и воды могут занижать итоги.").font(.caption).foregroundStyle(Theme.secondary)
        }.navigationTitle("Неделя в цифрах").navigationBarTitleDisplayMode(.inline)
    }
}

struct ManualMeasurementsView: View {
    let store: HealthOSStore
    @State private var adding = false
    var body: some View {
        Page {
            let logs = store.events.filter { $0.kind == .measurement }
            if logs.isEmpty { HintPanel(icon: "waveform.path.ecg", title: "Свои показатели", text: "Сохраняйте результат, единицу и референс лаборатории в заметке. Измерения остаются на устройстве.") }
            ForEach(logs) { event in
                VStack(alignment: .leading, spacing: 8) {
                    Text(Format.date(event.date, year: true)).font(.caption).foregroundStyle(Theme.secondary)
                    HealthEventRow(event: event)
                }
            }
            ActionButton(title: "Добавить измерение", icon: "plus") { adding = true }
        }.navigationTitle("Свои измерения").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $adding) { HealthEventEditor(store: store, kind: .measurement) }
    }
}

func signed(_ value: Double) -> String { (value > 0 ? "+" : "") + HealthEvent.number(value) }
func sourceName(_ source: String) -> String { source.components(separatedBy: "|").first ?? source }
