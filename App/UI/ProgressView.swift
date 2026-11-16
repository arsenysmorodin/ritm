import Charts
import SwiftUI

struct TrainingProgressView: View {
    let store: JournalStore
    let health: HealthConnection
    @State private var section: Section = .exercises
    @State private var period: Period = .quarter
    @State private var loadingWeight = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scene
    @Environment(\.dynamicTypeSize) private var textSize

    private enum Section: String, CaseIterable { case exercises = "Упражнения", weight = "Вес тела" }
    private enum Period: Int, CaseIterable {
        case month = 30, quarter = 90, year = 365
        var title: String { "\(rawValue) дн." }
    }

    var body: some View {
        let shouldRefreshWeight = scene == .active && section == .weight
        Page {
            PageHeader(title: "Прогресс", caption: "Тренировки и вес тела") { EmptyView() }
            Picker("Раздел", selection: $section) {
                ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.progressPicker(textSize)
            switch section {
            case .exercises: exerciseList
            case .weight: weightHistory
            }
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        .task(id: shouldRefreshWeight) {
            if shouldRefreshWeight { await refreshWeight() }
        }
        .refreshable { if section == .weight { await refreshWeight() } }
    }

    @ViewBuilder private var exerciseList: some View {
        let stats = ExerciseProgress.summarize(store.journal.records)
        if stats.isEmpty {
            HintPanel(icon: "dumbbell", title: "Начните с одного подхода", text: "После первой тренировки здесь появятся динамика повторов и рабочие веса.")
        } else {
            LazyVStack(spacing: Theme.Space.sm) {
                ForEach(stats) { item in
                    NavigationLink {
                        ExerciseProgressView(progress: item)
                    } label: {
                        Panel(padding: Theme.Space.md) {
                            HStack(spacing: Theme.Space.md) {
                                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                    Text(item.name).font(.headline)
                                    Text(Format.workouts(item.points.count) + " · " + Format.sets(item.totalSets))
                                        .font(.subheadline).foregroundStyle(Theme.secondary)
                                    if item.bestWeight > 0 {
                                        Text("Макс. \(Format.weight(item.bestWeight)) кг")
                                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                                    }
                                }
                                Spacer(minLength: Theme.Space.xs)
                                Image(systemName: "chevron.right").font(.caption)
                                    .foregroundStyle(Theme.secondary).accessibilityHidden(true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }.buttonStyle(PressStyle())
                }
            }
        }
    }

    @ViewBuilder private var weightHistory: some View {
        if !health.isAvailable || !store.journal.healthEnabled {
            HintPanel(icon: "scalemass", title: "Вес тела из «Здоровья»", text: "Подключите Apple «Здоровье» во вкладке «Здоровье» и разрешите чтение веса тела.")
        } else {
            let cutoff = Calendar.current.date(byAdding: .day, value: 1 - period.rawValue, to: Calendar.current.startOfDay(for: .now)) ?? .distantPast
            let values = health.weightHistory.filter { $0.date >= cutoff }
            Picker("Период", selection: $period) {
                ForEach(Period.allCases, id: \.self) { Text($0.title).tag($0) }
            }.progressPicker(textSize)
            let weights = values.map(\.kilograms)
            if let recent = values.last, let first = values.first, let low = weights.min(), let high = weights.max() {
                let change = recent.kilograms - first.kilograms
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        MetricValue(title: "Последний вес", value: "\(Format.weight(recent.kilograms)) кг")
                        Text(values.count > 1 ? "\(change > 0 ? "+" : "")\(Format.weight(change)) кг за выбранный период" : Format.date(recent.date))
                            .font(.subheadline).foregroundStyle(Theme.secondary)
                        Chart(values) { point in
                            LineMark(x: .value("Дата", point.date), y: .value("Вес, кг", point.kilograms))
                                .foregroundStyle(Theme.accent)
                            PointMark(x: .value("Дата", point.date), y: .value("Вес, кг", point.kilograms))
                                .symbolSize(values.count > 45 ? 6 : 20).foregroundStyle(Theme.accent)
                        }
                        .chartYScale(domain: (low - 0.5)...(high + 0.5))
                        .trendAxes()
                        .frame(height: 180)
                        .accessibilityLabel("График веса тела")
                    }
                    .privacySensitive()
                }
                Text("Последнее измерение за каждый день. Источник: Apple «Здоровье».")
                    .font(.footnote).foregroundStyle(Theme.secondary)
            } else if loadingWeight {
                Panel { StatusMessage(text: "Загружаем измерения веса…", loading: true) }
            } else {
                HintPanel(icon: "scalemass", title: "Нет измерений за период", text: "Запишите вес в Apple «Здоровье» или выберите другой период.")
            }
            if health.additionalPermissionsPending {
                ActionButton(title: "Разрешить чтение веса", icon: "heart", solid: false) {
                    Task { await health.connect(store); await refreshWeight() }
                }.disabled(health.isBusy)
            }
            if let issue = health.issue { StatusMessage(text: issue) }
        }
    }

    private func refreshWeight() async {
        loadingWeight = true
        defer { loadingWeight = false }
        await health.refreshWeight(store)
    }
}

private struct ExerciseProgressView: View {
    let progress: ExerciseProgress
    @State private var metric: Metric = .activity
    @Environment(\.dynamicTypeSize) private var textSize

    private enum Metric: String, CaseIterable { case activity, weight, volume }

    var body: some View {
        Page {
            PageHeader(title: progress.name, caption: Format.workouts(progress.points.count)) { EmptyView() }
            if progress.bestWeight > 0 {
                Picker("Показатель", selection: $metric) {
                    Text(activity).tag(Metric.activity)
                    Text("Макс. вес").tag(Metric.weight)
                    if progress.unit == .repetitions { Text("Объём").tag(Metric.volume) }
                }.progressPicker(textSize)
            }
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    if let latest = progress.points.last {
                        MetricValue(title: metric == .weight ? "Макс. вес в последней тренировке" :
                                    metric == .volume ? "Объём в последней тренировке" : "\(activity) в последней тренировке",
                                    value: "\(Format.weight(value(latest))) \(axisTitle)")
                    }
                    Chart(progress.points) { point in
                        LineMark(x: .value("Дата", point.date), y: .value(axisTitle, value(point))).foregroundStyle(Theme.accent)
                        PointMark(x: .value("Дата", point.date), y: .value(axisTitle, value(point))).foregroundStyle(Theme.accent)
                    }
                    .trendAxes()
                    .frame(height: 180)
                    .accessibilityLabel("\(axisTitle) по тренировкам")
                    if metric == .volume {
                        Text("Сумма веса × повторов по отмеченным подходам.").font(.footnote).foregroundStyle(Theme.secondary)
                    }
                }
            }
            SectionHeading(title: "По тренировкам")
            LazyVStack(spacing: Theme.Space.sm) {
                ForEach(progress.points.reversed()) { point in
                    Panel(padding: Theme.Space.md) {
                        let layout = textSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.sm)) : AnyLayout(HStackLayout())
                        layout {
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                Text(Format.date(point.date)).font(.subheadline.weight(.semibold))
                                Text(Format.sets(point.sets)).font(.subheadline).foregroundStyle(Theme.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(Format.weight(value(point))) \(axisTitle)").font(Theme.number)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var activity: String { progress.unit == .seconds ? "Время" : "Повторы" }
    private var axisTitle: String {
        switch metric {
        case .activity: progress.unit.short
        case .weight: "кг"
        case .volume: "кг·повт."
        }
    }

    private func value(_ point: ExerciseProgress.Point) -> Double {
        switch metric {
        case .activity: Double(point.total)
        case .weight: point.bestWeight
        case .volume: point.volume
        }
    }
}

private extension View {
    @ViewBuilder func progressPicker(_ textSize: DynamicTypeSize) -> some View {
        if textSize >= .xxxLarge {
            pickerStyle(.menu)
                .font(.headline)
                .frame(minHeight: Theme.touch)
        } else {
            pickerStyle(.segmented)
        }
    }
}

extension View {
    func trendAxes(showsTime: Bool = false) -> some View {
        chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) {
                if showsTime {
                    AxisValueLabel(format: .dateTime.hour().minute().locale(Format.russian), collisionResolution: .greedy)
                        .foregroundStyle(Theme.secondary)
                } else {
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(Format.russian), collisionResolution: .greedy)
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel().foregroundStyle(Theme.secondary)
            }
        }
    }
}
