import SwiftUI

struct ExperimentsView: View {
    let store: HealthOSStore
    @State private var adding = false
    var body: some View {
        Page {
            if store.experiments.isEmpty {
                HintPanel(icon: "flask", title: "Проверьте одну привычку", text: "Например, сравните привычный вечер с вечером без экрана. Заранее выберите исход и правило соблюдения. Приложение чередует условия A и B.")
            }
            ForEach(store.experiments) { experiment in
                NavigationLink { ExperimentDetail(store: store, experimentID: experiment.id) } label: {
                    Panel {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(experiment.title).font(.title3.weight(.semibold)).foregroundStyle(Theme.primary)
                            Text(experiment.outcome.title).font(.subheadline).foregroundStyle(Theme.secondary)
                            Text("\(experiment.totalDays) дн. · \(experiment.finished ? "Завершён" : Date.now < experiment.startsAt ? "Запланирован" : Date.now >= experiment.endsAt ? "Период закончен" : "В процессе")")
                                .font(.caption).foregroundStyle(Theme.secondary)
                        }
                    }
                }.buttonStyle(PressStyle()).accessibilityIdentifier("experiment.\(experiment.id)")
            }
            ActionButton(title: "Новый эксперимент", icon: "plus") { adding = true }
            Text("Выбирайте безопасные бытовые привычки с обратимым эффектом. Эксперименты с назначенными лекарствами и их дозами требуют участия врача.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }.navigationTitle("Эксперименты").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $adding) { ExperimentEditor(store: store) }
    }
}

struct ExperimentEditor: View {
    let store: HealthOSStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = HealthExperiment()
    var body: some View {
        NavigationStack {
            Form {
                Section("Одна привычка") {
                    TextField("Название эксперимента", text: $draft.title)
                    TextField("A: обычный режим", text: $draft.conditionA, axis: .vertical)
                    TextField("B: изменение", text: $draft.conditionB, axis: .vertical)
                    Picker("Основной исход", selection: $draft.outcome) {
                        ForEach(HealthMeasure.outcomes) { Text($0.title).tag($0) }
                    }
                }
                Section("План до начала") {
                    DatePicker("Первый день", selection: $draft.startsAt, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                    Stepper("Длина блока: \(draft.blockDays) дн.", value: $draft.blockDays, in: 2...28)
                        .onChange(of: draft.blockDays) { _, value in draft.adaptationDays = min(draft.adaptationDays, value - 1) }
                    Stepper("Адаптация в начале блока: \(draft.adaptationDays) дн.", value: $draft.adaptationDays, in: 0...(draft.blockDays - 1))
                    Text("Четыре блока, по два A и B. Порядок внутри каждой пары выбирается случайно один раз при сохранении. Дни адаптации исключаются заранее.")
                        .font(.caption).foregroundStyle(Theme.secondary)
                    Stepper("Минимум соблюдения: \(draft.minimumAdherence)%", value: $draft.minimumAdherence, in: 50...100, step: 5)
                    TextField("Что значит «условие соблюдено»?", text: $draft.rule, axis: .vertical).lineLimit(2...5)
                    TextField("Что сохраняем одинаковым, возможный перенос эффекта", text: $draft.notes, axis: .vertical).lineLimit(2...5)
                }
                Section { Text("После сохранения условия и исход фиксируются. Для сна результат относится к следующему утру. Выберите адаптацию с учётом возможного долгого эффекта привычки.").font(.caption).foregroundStyle(Theme.secondary) }
                if let error = store.error { Text(error).foregroundStyle(Theme.warning) }
            }
            .navigationTitle("Новый эксперимент").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        draft.startsAt = Calendar.current.startOfDay(for: draft.startsAt)
                        draft.blocks = (0..<2).flatMap { _ in Bool.random() ? [false, true] : [true, false] }
                        if store.saveExperiment(draft) { dismiss() }
                    }
                }
            }
        }
    }
}

struct ExperimentDetail: View {
    let store: HealthOSStore
    let experimentID: UUID
    @State private var confirmFinish = false
    @Environment(\.ritmAccent) private var accent
    private var experiment: HealthExperiment? { store.experiments.first { $0.id == experimentID } }
    var body: some View {
        Page {
            if let plan = experiment {
                Text(plan.title).font(Theme.screenTitle)
                Text("\(Format.date(plan.startsAt)) — \(Format.date(plan.endsAt.addingTimeInterval(-1)))").font(.subheadline).foregroundStyle(Theme.secondary)
                if let assignment = plan.assignment(on: .now), !plan.finished {
                    Panel {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Сегодня: \(assignment.isB ? "B" : "A")").font(.headline).foregroundStyle(accent)
                            Text(assignment.isB ? plan.conditionB : plan.conditionA).font(.title3.weight(.semibold))
                            if assignment.adaptation { Text("День адаптации. Не входит в итоговое сравнение.").font(.subheadline).foregroundStyle(Theme.secondary) }
                            Text(plan.rule).font(.subheadline)
                            let mark = store.events.first { $0.kind == .experiment && $0.linkedID == plan.id && Calendar.current.isDateInToday($0.date) }
                            ActionButton(title: mark?.ratings["adhered"] == 1 ? "Соблюдено ✓" : "Условие соблюдено", icon: "checkmark") { store.markExperiment(plan, adhered: true) }
                            Button(mark?.ratings["adhered"] == 0 ? "Не соблюдено ✓" : "Не получилось соблюсти") { store.markExperiment(plan, adhered: false) }.frame(minHeight: 44)
                        }
                    }
                }
                let report = HealthAnalytics.report(plan, days: store.days, events: store.events)
                Panel {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeading(title: "Наблюдаемый результат")
                        ComparisonPanel(result: report.comparison, metric: plan.outcome, labelA: "A", labelB: "B")
                        Text("Соблюдение: \(report.adherence.map { HealthEvent.number($0) + "%" } ?? "—"). Отметок \(report.recordedAdherence) из \(report.expectedDays) подходящих дней. Нет исхода: \(report.missingOutcomes). Дней адаптации: \(report.adaptationDays).")
                            .font(.subheadline).foregroundStyle(Theme.secondary)
                        if let adherence = report.adherence, adherence < Double(plan.minimumAdherence) {
                            Text("Соблюдение ниже заданных \(plan.minimumAdherence)%. Итог трудно интерпретировать.").font(.subheadline).foregroundStyle(Theme.warning)
                        }
                        Text("Группы определены назначенным условием, включая дни несоблюдения. Четырёх блоков недостаточно для надёжного интервала эффекта. Важны повторяемость по блокам и возможный перенос эффекта.")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
                SectionHeading(title: "План и средние по блокам")
                ForEach(Array(report.blocks.enumerated()), id: \.offset) { index, block in
                    HStack(alignment: .top, spacing: 12) {
                        Text(block.isB ? "B" : "A").font(.system(.title, design: .monospaced, weight: .semibold))
                            .foregroundStyle(block.isB ? accent : Theme.secondary).frame(width: 38)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Блок \(index + 1) · \(plan.blockDays) дн.").font(.headline)
                            Text(block.isB ? plan.conditionB : plan.conditionA).font(.subheadline).foregroundStyle(Theme.secondary)
                            Text(block.mean.map { "\(HealthEvent.number($0)) \(plan.outcome.unit) · \(block.count) дн. с данными" } ?? "Данных пока нет").font(.subheadline).monospacedDigit()
                        }
                    }.accessibilityElement(children: .combine)
                }
                if !plan.notes.isEmpty { Text(plan.notes).font(.subheadline).foregroundStyle(Theme.secondary) }
                if !plan.finished { Button("Завершить эксперимент") { confirmFinish = true }.frame(minHeight: 44) }
            }
        }.navigationTitle("Эксперимент").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Завершить эксперимент?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Завершить") { if var copy = experiment { copy.finished = true; _ = store.saveExperiment(copy) } }
            }
    }
}
