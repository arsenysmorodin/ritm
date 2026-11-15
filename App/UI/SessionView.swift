import SwiftUI

struct SessionView: View {
    let store: JournalStore
    let health: HealthConnection
    var onFinish: (WorkoutRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var confirmDiscard = false
    @State private var confirmFinish = false
    @State private var editing: SetSelection?
    @State private var remove: LoggedExercise?
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
                    ForEach(draft.exercises) { exercise in exercisePanel(exercise) }
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
                .sheet(item: $editing) { picked in
                    SetEditor(selection: picked) { set in
                        store.updateWorkout { current in
                            guard let e = current.exercises.firstIndex(where: { $0.id == picked.exerciseID }),
                                  let s = current.exercises[e].sets.firstIndex(where: { $0.id == set.id }) else { return }
                            current.exercises[e].sets[s] = set
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
                    Text("Подходы").font(.caption).foregroundStyle(Ink.muted)
                    Text("\(draft.marked) / \(draft.total)").font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Ink.lilac)
                }
            }
        }
    }

    private func exercisePanel(_ exercise: LoggedExercise) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.plan.name).font(.headline).accessibilityAddTraits(.isHeader)
                        Text("\(exercise.plan.sets) × \(exercise.plan.target) \(exercise.plan.unit.short)").font(.caption).foregroundStyle(Ink.muted)
                    }
                    Spacer()
                    Menu {
                        Button("Добавить подход", systemImage: "plus") {
                            store.updateWorkout { draft in
                                guard let e = draft.exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
                                let last = draft.exercises[e].sets.last
                                draft.exercises[e].sets.append(LoggedSet(value: last?.value ?? exercise.plan.target, weight: last?.weight ?? exercise.plan.weight))
                            }
                        }
                        Button("Удалить упражнение", systemImage: "trash", role: .destructive) { remove = exercise }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }.accessibilityLabel("Действия: \(exercise.plan.name)")
                }
                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                    HStack(spacing: 8) {
                        Text("\(index + 1)").font(.system(.subheadline, design: .rounded, weight: .medium)).monospacedDigit()
                            .frame(minWidth: 25).foregroundStyle(Ink.muted).accessibilityHidden(true)
                        Button {
                            editing = SetSelection(exerciseID: exercise.id, index: index + 1, unit: exercise.plan.unit, set: set)
                        } label: {
                            HStack {
                                Text("\(set.value) \(exercise.plan.unit.short)")
                                if set.weight > 0 { Text("\(Format.weight(set.weight)) кг").foregroundStyle(Ink.muted) }
                                Spacer(minLength: 4)
                                Image(systemName: "pencil").font(.caption).foregroundStyle(Ink.muted)
                            }.font(.subheadline).frame(minHeight: 44)
                        }.buttonStyle(PressStyle())
                            .accessibilityLabel("Изменить подход \(index + 1): \(set.value) \(exercise.plan.unit.short)" + (set.weight > 0 ? ", \(Format.weight(set.weight)) кг" : ""))
                        Button {
                            store.toggleSet(exerciseID: exercise.id, setID: set.id)
                        } label: {
                            Image(systemName: set.complete ? "checkmark.circle.fill" : "circle")
                                .font(.title2).foregroundStyle(set.complete ? Ink.peach : Ink.lilac)
                                .frame(width: 44, height: 44)
                        }.buttonStyle(PressStyle())
                            .accessibilityLabel(set.complete ? "Снять отметку с подхода \(index + 1)" : "Отметить подход \(index + 1)")
                    }
                    .padding(.leading, 4).background(Ink.raised, in: RoundedRectangle(cornerRadius: 10))
                }
            }
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
    let save: (LoggedSet) -> Void
    @State private var value: String
    @State private var weight: String
    @Environment(\.dismiss) private var dismiss

    init(selection: SetSelection, save: @escaping (LoggedSet) -> Void) {
        self.selection = selection
        self.save = save
        _value = State(initialValue: String(selection.set.value))
        _weight = State(initialValue: selection.set.weight > 0 ? Format.weight(selection.set.weight) : "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(selection.unit.label, text: $value).numericKeyboard().accessibilityLabel(selection.unit.label)
                TextField("Вес, кг", text: $weight).numericKeyboard(decimal: true).accessibilityLabel("Вес в килограммах")
            }
            .formTint()
            .navigationTitle("Подход \(selection.index)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        guard let newValue = Int(value.trimmed), let newWeight = validWeight(weight) else { return }
                        var set = selection.set
                        set.value = newValue
                        set.weight = newWeight
                        save(set)
                        dismiss()
                    }.disabled(!(1...3600).contains(Int(value.trimmed) ?? 0) || validWeight(weight) == nil)
                }
            }
        }
    }
}
