import SwiftUI
import Charts

struct HealthInsightsView: View {
    let store: HealthOSStore
    let journal: JournalStore
    @Environment(HealthOSBridge.self) private var bridge
    @State private var metric = HealthMeasure.sleepMinutes
    @State private var period = 28
    @State private var showMetrics = false
    @State private var showConnections = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            Page(spacing: 16) {
                if !store.isReadable {
                    HintPanel(icon: "externaldrive.badge.exclamationmark", title: "История недоступна", text: store.error ?? "Повторите загрузку данных.")
                    Button("Повторить") { store.reload() }.frame(minHeight: 44)
                } else {
                    metricMenu.id("insights.top")
                    Picker("Период сравнения", selection: $period) {
                        Text("7 дней").tag(7); Text("28 дней").tag(28); Text("90 дней").tag(90)
                    }.pickerStyle(.segmented).accessibilityIdentifier("insights.period")
                    let result = HealthAnalytics.comparePeriods(metric: metric, days: store.days, length: period)
                    BentoCard(emphasis: .raised) {
                        ComparisonPanel(result: result, metric: metric, labelA: "Раньше", labelB: "Сейчас",
                                        caption: "Последние \(period) дней к предыдущим \(period)")
                    }
                    let end = Calendar.current.startOfDay(for: .now)
                    let start = Calendar.current.date(byAdding: .day, value: -period, to: end) ?? end
                    let days = store.days.filter { $0.date >= start && $0.date < end && $0.values[metric] != nil &&
                        ($0.sources[metric] ?? "Неизвестный источник") == result.source }
                    InsightHistoryChart(days: days, metric: metric)
                    NavigationLink { HealthMetricDetail(store: store, metric: metric) } label: {
                        HStack {
                            Text("История показателя")
                            Spacer()
                            Image(systemName: "arrow.up.right").accessibilityHidden(true)
                        }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }.buttonStyle(PressStyle()).accessibilityIdentifier("insights.history")
                    Button { showConnections = true } label: {
                        BentoCard {
                            HStack(spacing: 14) {
                                Image(systemName: "point.3.connected.trianglepath.dotted").font(.title2).foregroundStyle(Theme.reference).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Связи привычек").font(.headline)
                                    Text("Сон, еда, кофеин и ваш результат").font(.subheadline).foregroundStyle(Theme.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.secondary).accessibilityHidden(true)
                            }.frame(minHeight: 64)
                        }
                    }.buttonStyle(PressStyle()).accessibilityIdentifier("insights.connections")
                    LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                        NavigationLink { WeeklyHealthReport(store: store) } label: {
                            InsightRouteTile(title: "Итоги недели", icon: "calendar", subtitle: "8 показателей")
                        }.accessibilityIdentifier("insights.week")
                        NavigationLink { ExperimentsView(store: store) } label: {
                            InsightRouteTile(title: "Эксперименты", icon: "flask", subtitle: "Проверить привычку")
                        }.accessibilityIdentifier("dynamics.experiments")
                    }.buttonStyle(PressStyle())
                    Button("Все показатели", systemImage: "square.grid.2x2") { showMetrics = true }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    if store.isImporting { StatusMessage(text: "Обновляем историю…", loading: true) }
                }
            }
            .onChange(of: metric) { _, _ in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("insights.top", anchor: .top) }
            }
        }
        .navigationTitle("Динамика").navigationBarTitleDisplayMode(.large)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { showMetrics = true } label: { Image(systemName: "list.bullet") }
                .accessibilityLabel("Выбрать показатель").accessibilityIdentifier("insights.all")
        } }
        .sheet(isPresented: $showMetrics) {
            InsightMetricChooser(store: store, selected: metric) { metric = $0 }
        }
        .sheet(isPresented: $showConnections) { HealthConnectionsView(store: store, journal: journal) }
        .refreshable { await bridge.refresh(journal, daily: store, force: true) }
    }

    private var metricMenu: some View {
        Menu {
            ForEach(HealthMeasure.allCases) { item in
                Button { metric = item } label: { Label(item.insightTitle, systemImage: item.insightIcon) }
                    .accessibilityIdentifier("insights.choose.\(item.rawValue)")
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: metric.insightIcon).foregroundStyle(Theme.reference).accessibilityHidden(true)
                Text(metric.insightTitle).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).accessibilityHidden(true)
                Spacer()
            }.foregroundStyle(Theme.primary).frame(minHeight: 44)
        }.accessibilityIdentifier("insights.metric").accessibilityLabel("Показатель: \(metric.insightTitle)")
    }
}

private struct InsightRouteTile: View {
    let title: String
    let icon: String
    let subtitle: String
    var body: some View {
        BentoCard {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.title3).foregroundStyle(Theme.reference).accessibilityHidden(true)
                Text(title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        }.multilineTextAlignment(.leading)
    }
}

struct ComparisonPanel: View {
    let result: HealthComparison
    let metric: HealthMeasure
    var labelA = "A"
    var labelB = "B"
    var kind: ComparisonKind = .periods
    var caption: String? = nil
    var exposure: HealthExposure? = nil
    @State private var details = false
    @Environment(\.ritmAccent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize
    private var readout: ComparisonReadout { .init(result: result, kind: kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                Text(readout.headline).font(.subheadline.weight(.semibold))
                    .foregroundStyle(readout.signal == .reversed ? Theme.warning : Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("comparison.headline")
                Spacer(minLength: 0)
                Button { details = true } label: { Image(systemName: "info.circle").frame(width: 44, height: 44) }
                    .padding(.top, -12).padding(.trailing, -10)
                    .accessibilityLabel("Как рассчитано сравнение")
                    .accessibilityIdentifier(kind == .association ? "comparison.associationInfo" : "comparison.info")
            }
            if readout.hasData, let delta = result.delta {
                if kind == .association, let validation = result.validationDelta {
                    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                    layout {
                        deltaValue(delta, title: "Первые данные", prominent: false)
                        deltaValue(validation, title: "Новые дни", prominent: true)
                    }.accessibilityIdentifier("comparison.validation")
                } else {
                    Text(InsightFormat.delta(delta, metric: metric))
                        .font(.system(.largeTitle, design: .monospaced, weight: .semibold))
                        .foregroundStyle(accent).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("comparison.delta")
                }
            } else {
                Text("Нужно по 3 дня в обеих группах").font(.subheadline).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let caption { Text(caption).font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
            let geometry = ComparisonBarGeometry([result.meanA, result.meanB].compactMap { $0 })
            bar(labelA, mean: result.meanA, count: result.a.count, geometry: geometry, current: false)
            bar(labelB, mean: result.meanB, count: result.b.count, geometry: geometry, current: true)
            if kind == .association {
                Label("Наблюдение, не причина", systemImage: "magnifyingglass")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
        }
        .sheet(isPresented: $details) {
            ComparisonDetails(result: result, metric: metric, kind: kind, exposure: exposure)
        }
    }

    private func deltaValue(_ value: Double, title: String, prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(Theme.secondary)
            Text(InsightFormat.delta(value, metric: metric)).font(.system(.title2, design: .monospaced, weight: .semibold))
                .foregroundStyle(prominent ? (readout.signal == .reversed ? Theme.warning : accent) : Theme.primary)
                .fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }
    private func bar(_ title: String, mean: Double?, count: Int, geometry: ComparisonBarGeometry, current: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            layout {
                Text(title).font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 6) }
                Text(mean.map { InsightFormat.value($0, metric: metric) } ?? "—")
                    .font(.system(.headline, design: .monospaced, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            }
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 3).fill(Theme.border.opacity(0.4))
                if let mean {
                    RoundedRectangle(cornerRadius: 3).fill(current ? accent : Theme.secondary)
                        .frame(width: proxy.size.width * geometry.width(mean))
                        .offset(x: proxy.size.width * geometry.start(mean))
                }
                if geometry.lower < 0 {
                    Rectangle().fill(Theme.primary.opacity(0.7)).frame(width: 1)
                        .offset(x: proxy.size.width * geometry.zero)
                }
            }.frame(height: 8).accessibilityHidden(true)
            Text("\(count) дн. с данными").font(.caption2).foregroundStyle(Theme.secondary)
        }.accessibilityElement(children: .combine)
    }
}

private struct ComparisonDetails: View {
    let result: HealthComparison
    let metric: HealthMeasure
    let kind: ComparisonKind
    let exposure: HealthExposure?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Данные") {
                    if kind == .periods { Text("Сравниваются два соседних периода из полных дней. Сегодняшний незавершённый день не входит в сравнение.") }
                    LabeledContent("Первая группа", value: "\(result.a.count) дн.")
                    LabeledContent("Вторая группа", value: "\(result.b.count) дн.")
                    if !result.source.isEmpty { LabeledContent("Источник", value: sourceName(result.source)) }
                    if result.excludedSources > 0 { LabeledContent("Другой источник · исключено", value: "\(result.excludedSources) дн.") }
                }
                if kind == .association {
                    Section("Условие") {
                        if let exposure { Text(exposure.title) }
                        Text("Для ночных показателей и пульса в покое учитывается предшествующий день. Порог разделения групп — условие сравнения, а не рекомендация.")
                        if exposure == .supplement { Text("Сравниваются только явные отметки «принято» и «пропущено» выбранной добавки.") }
                    }
                    Section("Проверка на новых днях") {
                        Text("Первые 70% наблюдений используются для поиска различия; последние 30% — для отдельной проверки.")
                        if let validation = result.validationDelta {
                            LabeledContent("Разница на новых днях", value: InsightFormat.delta(validation, metric: metric))
                        } else { Text("Нужно хотя бы по 4 наблюдения в каждой группе последних 30% истории.") }
                    }
                }
                Section("Неопределённость") {
                    if let interval = result.interval {
                        Text("Описательный 95% интервал: \(InsightFormat.delta(interval.lowerBound, metric: metric)) … \(InsightFormat.delta(interval.upperBound, metric: metric)).")
                        Text("Перевыборка календарными неделями, 800 повторов.")
                    } else { Text(kind == .experiment ? "Интервал эффекта в отчёте эксперимента не оценивается." : "Недостаточно недель для оценки неопределённости блоками.") }
                }
                Section("Что учитывать") {
                    Text("Пустые дни не считаются нулями. Используются наблюдения одного источника. Средние питания и воды могут быть занижены неполным дневником.")
                    if kind == .association {
                        Text("Связь не доказывает причину. Время, стресс, питание и тренировки могут меняться вместе. Временной тренд не скорректирован.")
                        if result.contextDays > 0 { Text("События режима отмечены в \(result.contextDays) дн. выборки.") }
                        if let steps = result.stepsDifference { Text("Активность групп различается в среднем на \(signed(steps)) шагов.") }
                    }
                }
            }.navigationTitle("Как рассчитано").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }.presentationDetents([.large])
    }
}

private struct HealthConnectionsView: View {
    let store: HealthOSStore
    let journal: JournalStore
    @State private var exposure = HealthExposure.lateCaffeine
    @State private var outcome = HealthMeasure.sleepMinutes
    @State private var supplementID: UUID?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Page(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Привычка", selection: $exposure) {
                        ForEach(HealthExposure.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.menu).accessibilityIdentifier("connections.exposure").frame(minHeight: 44)
                    Picker("Показатель", selection: $outcome) {
                        ForEach(HealthMeasure.outcomes) { Text($0.insightTitle).tag($0) }
                    }.pickerStyle(.menu).accessibilityIdentifier("connections.outcome").frame(minHeight: 44)
                    if exposure == .supplement {
                        Picker("Добавка", selection: $supplementID) {
                            Text("Выберите продукт").tag(Optional<UUID>.none)
                            ForEach(store.archive.supplements) { Text($0.name).tag(Optional($0.id)) }
                        }.frame(minHeight: 44)
                        if store.archive.supplements.isEmpty {
                            NavigationLink("Добавить продукт") { SupplementsView(store: store) }.frame(minHeight: 44)
                        }
                    }
                }
                let result = HealthAnalytics.pattern(exposure: exposure, outcome: outcome, days: store.days, events: store.events,
                    workouts: journal.journal.records, waterGoal: store.settings.waterGoal, supplementID: supplementID)
                BentoCard(emphasis: .raised) {
                    ComparisonPanel(result: result, metric: outcome, labelA: exposure.groupLabels.0,
                                    labelB: exposure.groupLabels.1, kind: .association, exposure: exposure)
                }
                NavigationLink { ExperimentsView(store: store) } label: {
                    HealthRouteRow(title: "Проверить экспериментом", subtitle: "Одна привычка, два режима", icon: "flask")
                }.buttonStyle(PressStyle())
            }.navigationTitle("Связи привычек").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}

private struct InsightHistoryChart: View {
    let days: [DailyHealth]
    let metric: HealthMeasure
    @State private var selection: Date?
    @Environment(\.ritmAccent) private var accent
    private var points: [InsightPlotPoint] { InsightPlotPoint.make(days, metric: metric) }
    var body: some View {
        let samples = points
        let segmentSizes = Dictionary(grouping: samples, by: \.series).mapValues(\.count)
        let selected = selection.flatMap { date in samples.first { Calendar.current.isDate($0.date, inSameDayAs: date) } }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(selection == nil ? "По дням" : selection!.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 6)
                if selection != nil {
                    Text(selected.map { InsightFormat.value($0.value, metric: metric) } ?? "Нет записи")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(accent)
                } else { Text(metric.unit).font(.caption).foregroundStyle(Theme.secondary) }
            }.accessibilityElement(children: .combine).accessibilityIdentifier("insights.chartValue")
            if samples.isEmpty {
                ContentUnavailableView("Нет записей за период", systemImage: metric.insightIcon,
                    description: Text("Выберите другой период или показатель."))
            } else if metric.isPulse {
                ForEach(samples.suffix(4).reversed()) { point in
                    HStack {
                        Text(point.date.formatted(.dateTime.day().month(.abbreviated))).foregroundStyle(Theme.secondary)
                        Spacer()
                        Text(InsightFormat.value(point.value, metric: metric)).fontWeight(.semibold).monospacedDigit()
                    }.font(.subheadline).accessibilityElement(children: .combine)
                }
            } else {
                Chart(samples) { point in
                    if metric.isBarMetric {
                        BarMark(x: .value("День", point.date, unit: .day), y: .value(metric.insightTitle, point.value))
                            .foregroundStyle(accent).cornerRadius(3)
                    } else {
                        LineMark(x: .value("День", point.date), y: .value(metric.insightTitle, point.value), series: .value("Непрерывный ряд", point.series))
                            .foregroundStyle(accent).lineStyle(StrokeStyle(lineWidth: 2))
                        if samples.count < 32 || segmentSizes[point.series] == 1 {
                            PointMark(x: .value("День", point.date), y: .value(metric.insightTitle, point.value))
                                .foregroundStyle(accent).symbolSize(14)
                        }
                    }
                    if let selected, selected.id == point.id {
                        RuleMark(x: .value("Выбранный день", point.date)).foregroundStyle(Theme.secondary.opacity(0.5))
                        PointMark(x: .value("День", point.date), y: .value(metric.insightTitle, point.value))
                            .foregroundStyle(accent).symbolSize(45)
                    }
                }
                .chartLegend(.hidden).chartXSelection(value: $selection)
                .chartGesture { proxy in
                    SpatialTapGesture().onEnded { event in proxy.selectXValue(at: event.location.x) }
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.twoDigits)).foregroundStyle(Theme.secondary)
                } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Theme.border.opacity(0.6))
                    AxisValueLabel().foregroundStyle(Theme.secondary)
                } }
                .frame(height: 176)
                .accessibilityLabel("\(metric.insightTitle), история по дням. \(samples.count) записей. Точные значения доступны в истории показателя.")
                .accessibilityIdentifier("insights.chart")
            }
        }.padding(.top, 6)
            .onChange(of: metric) { _, _ in selection = nil }
            .onChange(of: days.map(\.date)) { _, _ in selection = nil }
    }
}

struct HealthMetricDetail: View {
    let store: HealthOSStore
    let metric: HealthMeasure
    @State private var period = 90
    @State private var selectedSource = ""
    @State private var statistics = false
    private var history: [DailyHealth] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -period, to: .now) ?? .distantPast
        return store.days.filter { $0.date >= cutoff && $0.values[metric] != nil &&
            (selectedSource.isEmpty || $0.sources[metric] == selectedSource) }.sorted { $0.date < $1.date }
    }
    var body: some View {
        Page(spacing: 16) {
            Picker("Период истории", selection: $period) {
                Text("30 дн.").tag(30); Text("90 дн.").tag(90); Text("Год").tag(365); Text("Всё").tag(36500)
            }.pickerStyle(.segmented)
            let sources = Array(Set(store.days.compactMap { $0.sources[metric] })).sorted()
            if sources.count > 1 {
                Picker("Источник", selection: $selectedSource) {
                    Text("Все источники").tag("")
                    ForEach(sources, id: \.self) { Text(sourceName($0)).tag($0) }
                }.pickerStyle(.menu).frame(minHeight: 44)
            }
            if let last = history.last, let value = last.values[metric] {
                BentoCard(emphasis: .raised) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Последняя запись · \(last.date.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        Text(InsightFormat.value(value, metric: metric)).font(Theme.metric).fixedSize(horizontal: false, vertical: true)
                    }
                }
                InsightHistoryChart(days: history, metric: metric)
                HStack {
                    Text("\(history.count) дн. с данными").font(.caption).foregroundStyle(Theme.secondary)
                    Spacer()
                    Button("О диапазоне", systemImage: "info.circle") { statistics = true }.font(.subheadline).frame(minHeight: 44)
                }
                NavigationLink { HealthMetricLog(store: store, metric: metric, days: history) } label: {
                    HealthRouteRow(title: "Все записи", subtitle: "Точные значения и источники", icon: "list.bullet.rectangle")
                }.buttonStyle(PressStyle()).accessibilityIdentifier("insights.records")
                ForEach(history.suffix(3).reversed()) { day in
                    InsightDayRow(day: day, metric: metric)
                }
            } else {
                ContentUnavailableView("Пока нет наблюдений", systemImage: metric.insightIcon,
                    description: Text("Выберите другой период или разрешите чтение показателя из «Здоровья»."))
            }
        }.navigationTitle(metric.insightTitle).navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $statistics) {
                NavigationStack {
                    Form {
                        let values = history.compactMap { $0.values[metric] }.sorted()
                        if !values.isEmpty {
                            Section("Личный диапазон · 10–90%") {
                                LabeledContent("От", value: InsightFormat.value(values[Int(Double(values.count - 1) * 0.1)], metric: metric))
                                LabeledContent("До", value: InsightFormat.value(values[Int(Double(values.count - 1) * 0.9)], metric: metric))
                                Text("Описывает ваши записи за выбранный период. Это не медицинская норма.")
                            }
                        }
                        Section { Text("Пропуски остаются пропусками. Линии не соединяют дни с пропущенными данными и разные источники.") }
                    }.navigationTitle("Личный диапазон").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { statistics = false } } }
                }
            }
    }
}

private struct HealthMetricLog: View {
    let store: HealthOSStore
    let metric: HealthMeasure
    let days: [DailyHealth]
    var body: some View {
        List(days.reversed()) { day in
            VStack(alignment: .leading, spacing: 5) {
                InsightDayRow(day: day, metric: metric)
                Text(sourceName(day.sources[metric] ?? "Ритм") + (day.counts[metric].map { " · \($0) записей" } ?? ""))
                    .font(.caption).foregroundStyle(Theme.secondary)
                ForEach(HealthOSLogic.events(store.events, on: day.date).filter { $0.kind == .context }) { Text($0.title).font(.caption) }
            }
        }.navigationTitle("Все записи").navigationBarTitleDisplayMode(.inline)
    }
}

private struct InsightDayRow: View {
    let day: DailyHealth
    let metric: HealthMeasure
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) { date; Spacer(minLength: 8); value }
            VStack(alignment: .leading, spacing: 5) { date; value }
        }.font(.subheadline).padding(.vertical, 5).accessibilityElement(children: .combine)
    }
    private var date: some View { Text(day.date.formatted(.dateTime.day().month(.abbreviated).year())).foregroundStyle(Theme.secondary) }
    private var value: some View { Text(day.values[metric].map { InsightFormat.value($0, metric: metric) } ?? "—").fontWeight(.semibold).monospacedDigit() }
}

struct WeeklyHealthReport: View {
    let store: HealthOSStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.ritmAccent) private var accent
    var body: some View {
        Page(spacing: 16) {
            Text("Средние за 7 полных дней").font(.subheadline).foregroundStyle(Theme.secondary)
            LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                ForEach([HealthMeasure.sleepMinutes, .hrv, .restingPulse, .steps, .water, .caffeine, .fiber, .daylightMinutes]) { metric in
                    let result = HealthAnalytics.comparePeriods(metric: metric, days: store.days, length: 7)
                    NavigationLink {
                        Page {
                            BentoCard(emphasis: .raised) {
                                ComparisonPanel(result: result, metric: metric, labelA: "Неделей раньше", labelB: "Последние 7 дней")
                            }
                            NavigationLink("История показателя") { HealthMetricDetail(store: store, metric: metric) }.frame(minHeight: 44)
                        }.navigationTitle(metric.insightTitle).navigationBarTitleDisplayMode(.inline)
                    } label: {
                        BentoCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(metric.insightTitle, systemImage: metric.insightIcon).font(.subheadline.weight(.semibold))
                                Text(result.meanB.map { InsightFormat.value($0, metric: metric) } ?? "—")
                                    .font(.system(.title3, design: .monospaced, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                                if ComparisonReadout(result: result).hasData, let delta = result.delta {
                                    Text(InsightFormat.delta(delta, metric: metric)).font(.subheadline.weight(.semibold)).foregroundStyle(accent)
                                } else { Text("Мало данных").font(.caption).foregroundStyle(Theme.secondary) }
                            }.frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
                        }.multilineTextAlignment(.leading)
                    }.buttonStyle(PressStyle())
                }
            }
            Text("Изменение к предыдущей неделе").font(.caption).foregroundStyle(Theme.secondary)
        }.navigationTitle("Итоги недели").navigationBarTitleDisplayMode(.inline)
    }
}

private struct InsightMetricChooser: View {
    let store: HealthOSStore
    let selected: HealthMeasure
    let choose: (HealthMeasure) -> Void
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss
    private var results: [HealthMeasure] {
        HealthMeasure.allCases.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.insightTitle.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { metric in
                    Button { choose(metric); dismiss() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: metric.insightIcon).frame(width: 24).foregroundStyle(Theme.reference).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(metric.insightTitle).foregroundStyle(Theme.primary)
                                if let day = store.days.last(where: { $0.values[metric] != nil }), let value = day.values[metric] {
                                    Text("\(InsightFormat.value(value, metric: metric)) · \(day.date.formatted(.dateTime.day().month(.twoDigits)))")
                                        .font(.caption).foregroundStyle(Theme.secondary)
                                } else { Text("Нет записей").font(.caption).foregroundStyle(Theme.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if metric == selected { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }.frame(minHeight: 44)
                    }.accessibilityIdentifier("insights.list.\(metric.rawValue)")
                }
                NavigationLink("Свои измерения") { ManualMeasurementsView(store: store) }
                if results.isEmpty { ContentUnavailableView.search(text: search) }
            }.searchable(text: $search, prompt: "Название показателя")
                .navigationTitle("Показатели").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
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

private extension HealthMeasure {
    var insightTitle: String {
        switch self {
        case .sleepMinutes: "Сон"
        case .energy: "Энергия по ощущениям"
        case .stress: "Стресс"
        default: title
        }
    }
    var insightIcon: String {
        switch self {
        case .sleepMinutes: "moon.zzz.fill"
        case .hrv: "waveform.path.ecg"
        case .restingPulse, .sleepingPulse: "heart.fill"
        case .respiration: "lungs.fill"
        case .oxygen: "o2.circle"
        case .temperature: "thermometer.medium"
        case .steps: "figure.walk"
        case .activeEnergy, .calories: "flame.fill"
        case .daylightMinutes: "sun.max.fill"
        case .weight: "scalemass.fill"
        case .fiber: "carrot.fill"
        case .protein: "fork.knife"
        case .water: "drop.fill"
        case .caffeine: "cup.and.saucer.fill"
        case .energy: "bolt.fill"
        case .stress: "brain.head.profile"
        }
    }
    var isPulse: Bool { self == .restingPulse || self == .sleepingPulse }
    var isBarMetric: Bool { [.sleepMinutes, .steps, .water, .caffeine, .activeEnergy, .calories, .daylightMinutes, .fiber, .protein].contains(self) }
}

private extension HealthExposure {
    var groupLabels: (String, String) {
        switch self {
        case .lateCaffeine: ("Кофеин раньше", "Ближе ко сну")
        case .lateMeal: ("Еда раньше", "Менее 3 ч до сна")
        case .eveningTraining: ("До 19:00", "После 19:00")
        case .fiber: ("Меньше 25 г", "От 25 г")
        case .daylight: ("Меньше 30 мин", "От 30 мин")
        case .stress: ("Оценка 1–3", "Оценка 4–5")
        case .waterGoal: ("Ниже цели", "Цель достигнута")
        case .supplement: ("Пропущено", "Принято")
        case .earlyBedtime: ("00:00–17:59", "18:00–23:59")
        }
    }
}

func signed(_ value: Double) -> String { (value > 0 ? "+" : "") + HealthEvent.number(value) }
func sourceName(_ source: String) -> String { source.components(separatedBy: "|").first ?? source }
