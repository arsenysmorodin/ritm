import Charts
import SwiftUI

struct HistoryView: View {
    @Environment(\.ritmAccent) private var accent
    let store: JournalStore
    let health: HealthConnection
    @Binding var selected: UUID?
    @State private var showProgress = false
    @State private var deleting: WorkoutRecord?

    var body: some View {
        let records = store.journal.records
        Page {
            PageHeader(title: "История", caption: "Завершённые тренировки") { EmptyView() }
            ActionButton(title: "Прогресс", icon: "chart.line.uptrend.xyaxis", solid: false) { showProgress = true }
            if records.isEmpty {
                HintPanel(icon: "list.bullet.rectangle", title: "Здесь появится первая запись", text: "Завершите тренировку, чтобы сохранить время, подходы и заметки.")
            } else {
                ActivityChart(records: records)
                SectionHeading(title: "Все тренировки")
                LazyVStack(spacing: 8) {
                    ForEach(records) { record in
                        Button { selected = record.id } label: { RecordRow(record: record) }.buttonStyle(PressStyle())
                    }
                }
            }
        }
        .sheet(isPresented: $showProgress) { NavigationStack { TrainingProgressView(store: store, health: health) } }
        .sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            if let record = store.journal.records.first(where: { $0.id == selected }) {
                NavigationStack {
                    Page {
                        PageHeader(title: record.name, caption: Format.date(record.startedAt, year: true)) {
                            IconBadge(icon: record.kind.icon, color: record.kind.color)
                        }
                        Panel {
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .top, spacing: Theme.Space.lg) {
                                    duration(record)
                                    Spacer(minLength: 0)
                                    sets(record)
                                }
                                VStack(alignment: .leading, spacing: Theme.Space.md) {
                                    duration(record)
                                    sets(record)
                                }
                            }
                        }
                        if let pulse = record.pulse { PulsePanel(points: pulse) }
                        VStack(alignment: .leading, spacing: 9) {
                            if record.fromWatch == true {
                                Label("Записано на Apple Watch", systemImage: "applewatch")
                                    .font(.subheadline).foregroundStyle(Theme.secondary)
                            }
                            if !record.exercises.isEmpty { SectionHeading(title: "Выполнено") }
                            ForEach(record.exercises) { exercise in
                                Panel {
                                    VStack(alignment: .leading, spacing: 7) {
                                        NavigationLink { ExercisePlanDetailView(plan: exercise.plan) } label: {
                                            HStack {
                                                Text(exercise.plan.name).font(.headline)
                                                Spacer(minLength: Theme.Space.sm)
                                                Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
                                            }
                                            .frame(minHeight: Theme.touch).contentShape(Rectangle())
                                        }
                                        if let block = record.blocks?.first(where: { $0.exerciseIDs.contains(exercise.plan.id) }) {
                                            Label(block.kind.title, systemImage: block.kind.icon)
                                                .font(.subheadline).foregroundStyle(Theme.secondary)
                                        }
                                        ForEach(exercise.steps) { step in
                                            let set = step.set
                                            Divider()
                                            logRow(
                                                set.dropStage.map { "Подход \(step.round) · дроп \($0)" } ?? step.title,
                                                value: "\(set.value) \(exercise.plan.unit.short)" + (set.weight > 0 ? "  ·  \(Format.weight(set.weight)) кг" : "")
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        if !record.exercises.isEmpty {
                            MuscleMap(muscles: .combined(record.exercises.map(\.plan.muscles)), title: "Мышцы тренировки")
                        }
                        if !record.notes.isEmpty {
                            VStack(alignment: .leading, spacing: 9) {
                                SectionHeading(title: "Заметка")
                                Panel { Text(record.notes).font(.subheadline) }
                            }
                        }
                        if record.healthExported {
                            Label("Сохранено в Apple «Здоровье»", systemImage: "heart.fill")
                                .font(.subheadline).foregroundStyle(accent)
                        } else if store.journal.healthEnabled && health.isAvailable {
                            let title = record.awaitsHealthExport ? "Повторить отправку" : "Отправить в «Здоровье»"
                            ActionButton(title: title, icon: "heart", solid: false) {
                                Task { await health.requestExport(record.id, from: store) }
                            }.disabled(health.isBusy)
                            if let issue = health.exportIssue, issue.id == record.id {
                                StatusMessage(text: issue.message)
                            } else if record.awaitsHealthExport {
                                Text("Ожидает отправки в «Здоровье».").font(.footnote).foregroundStyle(Theme.secondary)
                            }
                        }
                        Button("Удалить запись", role: .destructive) { deleting = record }
                            .font(.subheadline).frame(minHeight: 44)
                            .disabled(health.isBusy)
                    }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { selected = nil } } }
                    .alert("Удалить запись?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { item in
                        Button("Удалить", role: .destructive) {
                            if store.change({ $0.records.removeAll { $0.id == item.id } }) { selected = nil }
                            deleting = nil
                        }
                        Button("Отмена", role: .cancel) { deleting = nil }
                    } message: { item in
                        Text(item.healthExported ? "Запись исчезнет из «Ритма». Копия в Apple «Здоровье» останется." : "Запись будет удалена из истории.")
                    }
                    .storageAlert(store)
                }
            }
        }
    }

    private func duration(_ record: WorkoutRecord) -> some View {
        MetricValue(title: "Длительность", value: Format.duration(record.duration)).fixedSize(horizontal: true, vertical: false)
    }

    private func sets(_ record: WorkoutRecord) -> some View {
        MetricValue(title: "Подходы", value: Format.integer(record.sets)).fixedSize(horizontal: true, vertical: false)
    }

    private func logRow(_ title: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(title).font(.subheadline).foregroundStyle(Theme.secondary)
                Spacer(minLength: Theme.Space.sm)
                Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(title).font(.subheadline).foregroundStyle(Theme.secondary)
                Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
        }
        .padding(.vertical, Theme.Space.xs)
        .accessibilityElement(children: .combine)
    }
}

struct RecordRow: View {
    let record: WorkoutRecord
    var body: some View {
        Panel(padding: Theme.Space.md) {
            HStack(spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(record.name).font(.headline)
                    Text(Format.date(record.startedAt)).font(.subheadline).foregroundStyle(Theme.secondary)
                    Text("\(Format.duration(record.duration))  ·  \(Format.sets(record.sets))")
                        .font(.subheadline).monospacedDigit()
                }
                Spacer(minLength: Theme.Space.xs)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondary).accessibilityHidden(true)
            }.accessibilityElement(children: .combine)
        }
    }
}

private struct ActivityChart: View {
    @Environment(\.ritmAccent) private var accent
    let records: [WorkoutRecord]

    private var days: [ActivityDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let groups = Dictionary(grouping: records) { calendar.startOfDay(for: $0.startedAt) }
        return (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return ActivityDay(date: date, count: groups[date]?.count ?? 0)
        }
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                MetricValue(title: "Тренировки за последние 7 дней", value: Format.integer(days.reduce(0) { $0 + $1.count }))
                Chart(days) { day in
                    BarMark(x: .value("День", day.date, unit: .day), y: .value("Тренировки", day.count), width: .ratio(0.52))
                        .foregroundStyle(accent).cornerRadius(4)
                        .accessibilityLabel(Format.date(day.date)).accessibilityValue(Format.workouts(day.count))
                }
                .chartYScale(domain: 0...max(1, days.map(\.count).max() ?? 1))
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: days.map(\.date)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date.formatted(.dateTime.day().locale(Format.russian))).foregroundStyle(Theme.secondary)
                            }
                        }
                    }
                }
                .frame(height: 100)
            }
        }
    }

    private struct ActivityDay: Identifiable {
        var id: Date { date }
        let date: Date
        let count: Int
    }
}
