import SwiftUI

struct SessionView: View {
    let store: JournalStore
    let health: HealthConnection
    var onFinish: (WorkoutRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var adding = false
    @State private var confirmDiscard = false
    @State private var confirmFinish = false
    @State private var editing: SetSelection?
    @State private var remove: LoggedExercise?
    @State private var guide: ExercisePlan?
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            if let draft = store.journal.activeWorkout {
                Page {
                    PageHeader(title: draft.name, caption: "Тренировка в процессе") { EmptyView() }
                    stopwatch(draft)
                    if let pulse = draft.pulse, !pulse.isEmpty {
                        TimelineView(.periodic(from: .now, by: 10)) { context in
                            PulsePanel(points: pulse, live: true, now: context.date)
                        }
                    } else if health.isAvailable && store.journal.healthEnabled {
                        HintPanel(icon: "heart", title: "Пульс во время занятия", text: "Откройте «Ритм» на Apple Watch для живых замеров. Здесь также видны замеры из Apple «Здоровья» за время тренировки.")
                    }
                    if draft.exercises.isEmpty {
                        HintPanel(icon: "dumbbell", title: "С чего начнём?", text: "Добавьте первое упражнение и отмечайте выполненные подходы.")
                    }
                    let next = draft.nextStep?.id
                    ForEach(draft.sections) { section in
                        if let block = section.block {
                            blockPanel(section, block: block, next: next)
                        } else if let exercise = section.exercises.first {
                            exercisePanel(exercise, next: next)
                        }
                    }
                    ActionButton(title: "Добавить упражнение", icon: "plus", solid: false) { adding = true }
                    Panel {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Заметка").font(.headline)
                            TextField("Как прошла тренировка?", text: $notes, axis: .vertical)
                                .editAutocorrection().font(.subheadline).lineLimit(1...4)
                                .accessibilityLabel("Заметка о тренировке")
                                .onChange(of: notes) { _, new in store.updateWorkout { $0.notes = new } }
                        }
                    }
                    Button("Отменить тренировку", role: .destructive) { confirmDiscard = true }
                        .font(.subheadline).frame(minHeight: 44)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) { controls(draft) }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Свернуть") { dismiss() } }
                }
                .task(id: draft.id) { notes = draft.notes }
                .sheet(isPresented: $adding) {
                    ExerciseEditor(initial: ExercisePlan(name: "")) { plan in
                        store.updateWorkout { $0.exercises.append(LoggedExercise(plan)) }
                    }
                }
                .sheet(item: $guide) { plan in
                    NavigationStack {
                        ExercisePlanDetailView(plan: plan)
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { guide = nil } } }
                    }
                }
                .sheet(item: $editing) { picked in
                    SetEditor(selection: picked) { value, weight in
                        store.updateWorkout { current in
                            guard let e = current.exercises.firstIndex(where: { $0.id == picked.exerciseID }),
                                  let s = current.exercises[e].sets.firstIndex(where: { $0.id == picked.id }) else { return }
                            current.exercises[e].sets[s].value = value
                            current.exercises[e].sets[s].weight = weight
                        }
                    }
                }
                .alert("Отменить тренировку?", isPresented: $confirmDiscard) {
                    Button("Удалить черновик", role: .destructive) {
                        if store.change({ $0.activeWorkout = nil }) { dismiss() }
                    }
                    Button("Продолжить", role: .cancel) {}
                } message: { Text("Отмеченные подходы этой тренировки будут удалены.") }
                .alert("Завершить тренировку?", isPresented: $confirmFinish) {
                    Button("Сохранить тренировку") { finish() }
                    Button("Продолжить", role: .cancel) {}
                } message: { Text("В историю попадут только отмеченные подходы.") }
                .alert("Удалить упражнение?", isPresented: Binding(get: { remove != nil }, set: { if !$0 { remove = nil } }), presenting: remove) { exercise in
                    Button("Удалить", role: .destructive) {
                        store.updateWorkout { $0.exercises.removeAll { $0.id == exercise.id }; $0.restUntil = nil }
                        remove = nil
                    }
                    Button("Отмена", role: .cancel) { remove = nil }
                } message: { _ in Text("Все подходы упражнения будут удалены из этой тренировки.") }
                .storageAlert(store)
            }
        }
    }

    private func stopwatch(_ draft: ActiveWorkout) -> some View {
        Panel {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Время занятия").font(.caption).foregroundStyle(Ink.muted)
                    TimelineView(.periodic(from: draft.startedAt, by: 1)) { context in
                        Text(Format.clock(Int(context.date.timeIntervalSince(draft.startedAt))))
                            .font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
                            .accessibilityLabel("Время: \(Format.duration(max(0, Int(context.date.timeIntervalSince(draft.startedAt)))))")
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    let hasDrops = draft.exercises.contains { $0.plan.drops?.isEmpty == false }
                    Text(hasDrops ? "Этапы" : "Подходы").font(.caption).foregroundStyle(Ink.muted)
                    Text("\(draft.marked) / \(draft.total)").font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Ink.lilac)
                }
            }
        }
    }

    private func exercisePanel(_ exercise: LoggedExercise, next: UUID?) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.plan.name).font(.headline).accessibilityAddTraits(.isHeader)
                        Text("\(exercise.plan.sets) × \(exercise.plan.target) \(exercise.plan.unit.short)")
                            .font(.caption).foregroundStyle(Ink.muted)
                    }
                    Spacer()
                    exerciseMenu(exercise)
                }
                ForEach(exercise.steps) { step in
                    stepRow(step, grouped: false, next: next == step.id && exercise.plan.drops?.isEmpty == false)
                }
            }
        }
    }

    private func blockPanel(_ section: WorkoutSection, block: ExerciseBlock, next: UUID?) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Label(block.kind.title, systemImage: block.kind.icon).font(.headline).foregroundStyle(Ink.lilac)
                    Spacer()
                    Menu {
                        ForEach(section.exercises) { exercise in
                            Button(exercise.plan.name) { guide = exercise.plan }
                        }
                    } label: {
                        Image(systemName: "figure.strengthtraining.traditional").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Техника упражнений")
                }
                ForEach(section.rounds) { round in
                    Text("Раунд \(round.id)").font(.caption.weight(.semibold)).foregroundStyle(Ink.muted)
                    ForEach(round.steps) { step in stepRow(step, grouped: true, next: next == step.id) }
                }
            }
        }
    }

    private func exerciseMenu(_ exercise: LoggedExercise) -> some View {
        Menu {
            Button("Мышцы и техника", systemImage: "figure.strengthtraining.traditional") { guide = exercise.plan }
            Button("Добавить подход", systemImage: "plus") {
                store.updateWorkout { draft in
                    guard let index = draft.exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
                    draft.exercises[index].appendRound()
                }
            }
            Button("Удалить упражнение", systemImage: "trash", role: .destructive) { remove = exercise }
        } label: {
            Image(systemName: "ellipsis").frame(width: 44, height: 44)
        }
        .accessibilityLabel("Действия: \(exercise.plan.name)")
    }

    private func stepRow(_ step: WorkoutStep, grouped: Bool, next: Bool) -> some View {
        let set = step.set
        let quantity = "\(set.value) \(step.unit.short)"
        let weight = set.weight > 0 ? "\(Format.weight(set.weight)) кг" : ""
        let summary = [quantity, weight].filter { !$0.isEmpty }.joined(separator: " · ")
        let repetitions = step.unit == .repetitions
        let label = grouped && set.dropStage == nil ? step.name : step.title
        let layout = repetitions && dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 6))
        return layout {
            Button {
                editing = SetSelection(exerciseID: step.exerciseID, index: step.round, unit: step.unit, set: set)
            } label: {
                HStack(spacing: 5) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(set.dropStage != nil && grouped ? step.name + " · " + label : label)
                            .font(.subheadline.weight(.medium)).foregroundStyle(set.dropStage != nil ? Ink.lilac : Ink.primary)
                        if !repetitions || !weight.isEmpty {
                            Text(repetitions ? weight : summary).font(.caption).foregroundStyle(Ink.muted)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "pencil").font(.caption).foregroundStyle(Ink.muted)
                }
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Изменить \(step.title.lowercased()), \(step.name), \(summary)")
            HStack(spacing: 6) {
                if repetitions {
                    RepetitionControl(value: set.value, context: "\(step.name), \(step.title.lowercased())") { change in
                        adjustRepetitions(step, by: change)
                    } count: {
                        Text("\(set.value)")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Ink.primary)
                            .frame(minWidth: 30)
                            .accessibilityLabel(quantity)
                    }
                }
                Button {
                    store.toggleSet(exerciseID: step.exerciseID, setID: set.id)
                } label: {
                    Image(systemName: set.complete ? "checkmark.circle.fill" : "circle")
                        .font(.title2).foregroundStyle(set.complete ? Ink.peach : Ink.lilac)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel((set.complete ? "Снять отметку, " : "Отметить ") + step.title.lowercased() + ", " + step.name)
                .accessibilityHint(next ? "Следующий этап тренировки" : "")
            }
        }
        .padding(.leading, set.dropStage == nil ? 10 : 18)
        .background(Ink.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            if next { RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.lilac.opacity(0.65), lineWidth: 1).allowsHitTesting(false) }
        }
    }

    private func adjustRepetitions(_ step: WorkoutStep, by change: Int) {
        store.updateWorkout { draft in
            guard let exercise = draft.exercises.firstIndex(where: { $0.id == step.exerciseID }),
                  let set = draft.exercises[exercise].sets.firstIndex(where: { $0.id == step.id }) else { return }
            let value = draft.exercises[exercise].sets[set].value
            let current = min(max(value, exerciseQuantityRange.lowerBound), exerciseQuantityRange.upperBound)
            draft.exercises[exercise].sets[set].value = min(max(current + change, exerciseQuantityRange.lowerBound), exerciseQuantityRange.upperBound)
        }
    }

    private func controls(_ draft: ActiveWorkout) -> some View {
        VStack(spacing: 7) {
            if let rest = draft.restUntil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = draft.secondsLeft(at: context.date)
                    if seconds > 0 {
                        HStack {
                            Image(systemName: "timer").foregroundStyle(Ink.peach)
                            Text("Отдых").font(.subheadline)
                            Text(Format.clock(seconds)).font(.system(.headline, design: .rounded)).monospacedDigit()
                            Spacer()
                            Button("Пропустить") { store.updateWorkout { $0.restUntil = nil } }.font(.subheadline.weight(.medium)).frame(minHeight: 44)
                        }.padding(.horizontal, 5)
                    }
                }.id(rest)
            }
            ActionButton(title: "Завершить тренировку", icon: "checkmark", color: Ink.peach) {
                if draft.marked < draft.total { confirmFinish = true } else { finish() }
            }.disabled(draft.marked == 0)
        }
        .padding(.horizontal, 21).padding(.top, 7).padding(.bottom, 8)
        .frame(maxWidth: 602).frame(maxWidth: .infinity)
        .background(Ink.paper)
        .overlay(alignment: .top) { Divider() }
    }

    private func finish() {
        if let record = store.finish() {
            dismiss()
            onFinish(record)
        }
    }
}

struct SetSelection: Identifiable {
    var id: UUID { self.set.id }
    let exerciseID: UUID
    let index: Int
    let unit: ExerciseUnit
    var set: LoggedSet
}

private struct SetEditor: View {
    let selection: SetSelection
    let save: (Int, Double) -> Void
    @State private var value: String
    @State private var weight: String
    @Environment(\.dismiss) private var dismiss

    init(selection: SetSelection, save: @escaping (Int, Double) -> Void) {
        self.selection = selection
        self.save = save
        _value = State(initialValue: String(selection.set.value))
        _weight = State(initialValue: selection.set.weight > 0 ? Format.weight(selection.set.weight) : "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if selection.unit == .repetitions {
                    RepetitionField(text: $value)
                } else {
                    TextField(selection.unit.label, text: $value).numericKeyboard().accessibilityLabel(selection.unit.label)
                }
                TextField("Вес, кг", text: $weight).numericKeyboard(decimal: true).accessibilityLabel("Вес в килограммах")
            }
            .formTint()
            .navigationTitle(selection.set.dropStage.map { "Дроп \($0)" } ?? "Подход \(selection.index)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        guard let newValue = Int(value.trimmed), let newWeight = validWeight(weight) else { return }
                        save(newValue, newWeight)
                        dismiss()
                    }.disabled(!exerciseQuantityRange.contains(Int(value.trimmed) ?? 0) || validWeight(weight) == nil)
                }
            }
        }
    }
}
