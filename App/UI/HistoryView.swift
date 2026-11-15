import Charts
import SwiftUI

struct HistoryView: View {
    let store: JournalStore
    let health: HealthConnection
    @Binding var selected: UUID?
    @State private var showProgress = false
    @State private var deleting: WorkoutRecord?

    var body: some View {
        let records = store.journal.records
        Page {
            PageHeader(title: "История", caption: "Завершённые тренировки") { IconBadge(icon: "calendar") }
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
                            HStack(spacing: 14) {
                                Label(Format.duration(record.duration), systemImage: "clock")
                                Label(Format.sets(record.sets), systemImage: "checkmark.circle")
                            }.font(.subheadline)
                        }
                        if let pulse = record.pulse { PulsePanel(points: pulse) }
                        VStack(alignment: .leading, spacing: 9) {
                            if record.fromWatch == true {
                                Label("Записано на Apple Watch", systemImage: "applewatch")
                                    .font(.subheadline).foregroundStyle(Ink.lilac)
                            }
                            if !record.exercises.isEmpty { SectionHeading(title: "Выполнено") }
                            ForEach(record.exercises) { exercise in
                                Panel {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(exercise.plan.name).font(.headline)
                                        ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                                            HStack {
                                                Text("Подход \(index + 1)").foregroundStyle(Ink.muted)
                                                Spacer()
                                                Text("\(set.value) \(exercise.plan.unit.short)" + (set.weight > 0 ? " • \(Format.weight(set.weight)) кг" : ""))
                                            }.font(.subheadline)
                                        }
                                    }
                                }
                            }
                        }
                        if !record.notes.isEmpty {
                            VStack(alignment: .leading, spacing: 9) {
                                SectionHeading(title: "Заметка")
                                Panel { Text(record.notes).font(.subheadline) }
                            }
                        }
                        if record.healthExported {
                            Label("Сохранено в Apple «Здоровье»", systemImage: "heart.fill")
                                .font(.subheadline).foregroundStyle(Ink.lilac)
                        } else if store.journal.healthEnabled && health.isAvailable {
                            let title = record.awaitsHealthExport ? "Повторить отправку" : "Отправить в «Здоровье»"
                            ActionButton(title: title, icon: "heart", solid: false) {
                                Task { await health.requestExport(record.id, from: store) }
                            }.disabled(health.isBusy)
                            if let issue = health.exportIssue, issue.id == record.id {
                                Text(issue.message).font(.footnote).foregroundStyle(Ink.peach)
                            } else if record.awaitsHealthExport {
                                Text("Ожидает отправки в «Здоровье».").font(.footnote).foregroundStyle(Ink.muted)
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
}

struct RecordRow: View {
    let record: WorkoutRecord
    var body: some View {
        Panel(padding: 11) {
            HStack(spacing: 11) {
                IconBadge(icon: record.kind.icon, color: record.kind.color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.name).font(.subheadline.weight(.semibold))
                    Text("\(Format.date(record.startedAt)), \(Format.duration(record.duration))")
                        .font(.caption).foregroundStyle(Ink.muted)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Ink.muted)
            }.accessibilityElement(children: .combine)
        }
    }
}

private struct ActivityChart: View {
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
                SectionHeading(title: "Последние 7 дней")
                Text(Format.workouts(days.reduce(0) { $0 + $1.count })).font(.subheadline).foregroundStyle(Ink.muted)
                Chart(days) { day in
                    BarMark(x: .value("День", day.date, unit: .day), y: .value("Тренировки", day.count), width: .ratio(0.52))
                        .foregroundStyle(Ink.peach).cornerRadius(4)
                        .accessibilityLabel(Format.date(day.date)).accessibilityValue(Format.workouts(day.count))
                }
                .chartYScale(domain: 0...max(1, days.map(\.count).max() ?? 1))
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: days.map(\.date)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date.formatted(.dateTime.day().locale(Format.russian))).foregroundStyle(Ink.muted)
                            }
                        }
                    }
                }
                .frame(height: 92)
            }
        }
    }

    private struct ActivityDay: Identifiable {
        var id: Date { date }
        let date: Date
        let count: Int
    }
}
