import Charts
import SwiftUI

struct TrainingProgressView: View {
    let store: JournalStore
    let health: HealthConnection
    @State private var section: Section = .exercises
    @State private var period: Period = .quarter
    @Environment(\.dismiss) private var dismiss

    private enum Section: String, CaseIterable { case exercises = "Упражнения", weight = "Вес тела" }
    private enum Period: Int, CaseIterable {
        case month = 30, quarter = 90, year = 365
        var title: String { "\(rawValue) дн." }
    }

    var body: some View {
        Page {
            PageHeader(title: "Прогресс", caption: "Динамика тренировок и веса") { IconBadge(icon: "chart.line.uptrend.xyaxis") }
            Picker("Раздел", selection: $section) {
                ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            switch section {
            case .exercises: exerciseList
            case .weight: weightHistory
            }
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        .task(id: section) { if section == .weight { await health.refreshWeight(store) } }
        .refreshable { if section == .weight { await health.refreshWeight(store) } }
    }

    @ViewBuilder private var exerciseList: some View {
        let stats = ExerciseProgress.summarize(store.journal.records)
        if stats.isEmpty {
            HintPanel(icon: "dumbbell", title: "Начните с одного подхода", text: "После первой тренировки здесь появятся динамика повторов и рабочие веса.")
        } else {
            ForEach(stats) { item in
                NavigationLink {
                    ExerciseProgressView(progress: item)
                } label: {
                    Panel(padding: 12) {
                        HStack(spacing: 11) {
                            IconBadge(icon: "dumbbell", size: 38)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).font(.headline)
                                Text(Format.workouts(item.points.count) + " · " + Format.sets(item.totalSets))
                                    .font(.caption).foregroundStyle(Ink.muted)
                            }
                            Spacer()
                            if item.bestWeight > 0 {
                                Text("\(Format.weight(item.bestWeight)) кг").font(.subheadline.weight(.semibold)).foregroundStyle(Ink.peach)
                            }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ink.muted)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }.buttonStyle(PressStyle())
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
            }.pickerStyle(.segmented)
            let weights = values.map(\.kilograms)
            if let recent = values.last, let first = values.first, let low = weights.min(), let high = weights.max() {
                let change = recent.kilograms - first.kilograms
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(Format.weight(recent.kilograms)) кг").font(.largeTitle.weight(.semibold)).monospacedDigit()
                        Text(values.count > 1 ? "\(change > 0 ? "+" : "")\(Format.weight(change)) кг за выбранный период" : Format.date(recent.date))
                            .font(.subheadline).foregroundStyle(Ink.muted)
                        Chart(values) { point in
                            LineMark(x: .value("Дата", point.date), y: .value("Вес, кг", point.kilograms))
                                .foregroundStyle(Ink.peach)
                            PointMark(x: .value("Дата", point.date), y: .value("Вес, кг", point.kilograms))
                                .symbolSize(values.count > 45 ? 6 : 20).foregroundStyle(Ink.peach)
                        }
                        .chartYScale(domain: (low - 0.5)...(high + 0.5))
                        .frame(height: 175)
                        .accessibilityLabel("График веса тела")
                    }
                    .privacySensitive()
                }
                Text("Последнее измерение за каждый день. Источник: Apple «Здоровье».")
                    .font(.footnote).foregroundStyle(Ink.muted)
            } else {
                HintPanel(icon: "scalemass", title: "Нет измерений за период", text: "Запишите вес в Apple «Здоровье» или выберите другой период.")
            }
            if health.additionalPermissionsPending {
                ActionButton(title: "Разрешить чтение веса", icon: "heart", solid: false) {
                    Task { await health.connect(store); await health.refreshWeight(store) }
                }.disabled(health.isBusy)
            }
            if let issue = health.issue { Text(issue).font(.footnote).foregroundStyle(Ink.peach) }
        }
    }
}

private struct ExerciseProgressView: View {
    let progress: ExerciseProgress
    @State private var metric: Metric = .activity

    private enum Metric: String, CaseIterable { case activity, weight, volume }

    var body: some View {
        Page {
            PageHeader(title: progress.name, caption: Format.workouts(progress.points.count)) { IconBadge(icon: "dumbbell") }
            if progress.bestWeight > 0 {
                Picker("Показатель", selection: $metric) {
                    Text(activity).tag(Metric.activity)
                    Text("Макс. вес").tag(Metric.weight)
                    if progress.unit == .repetitions { Text("Объём").tag(Metric.volume) }
                }.pickerStyle(.segmented)
            }
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: metric == .weight ? "Самый тяжёлый подход" : metric == .volume ? "Объём по тренировкам" : "\(activity) по тренировкам")
                    Chart(progress.points) { point in
                        LineMark(x: .value("Дата", point.date), y: .value(axisTitle, value(point))).foregroundStyle(Ink.lilac)
                        PointMark(x: .value("Дата", point.date), y: .value(axisTitle, value(point))).foregroundStyle(Ink.peach)
                    }
                    .frame(height: 175)
                    .accessibilityLabel("\(axisTitle) по тренировкам")
                    if metric == .volume {
                        Text("Сумма веса × повторов по отмеченным подходам.").font(.footnote).foregroundStyle(Ink.muted)
                    }
                }
            }
            SectionHeading(title: "По тренировкам")
            ForEach(progress.points.reversed()) { point in
                Panel(padding: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Format.date(point.date)).font(.subheadline.weight(.semibold))
                            Text(Format.sets(point.sets)).font(.caption).foregroundStyle(Ink.muted)
                        }
                        Spacer()
                        Text("\(Format.weight(value(point))) \(axisTitle)").monospacedDigit().foregroundStyle(Ink.lilac)
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
