import SwiftUI

struct SessionView: View {
    @Environment(\.ritmAccent) private var accent
    let store: JournalStore
    let health: HealthConnection
    var onFinish: (WorkoutRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var adding = false
    @State private var confirmDiscard = false
    @State private var confirmFinish = false
    @State private var editing: SetSelection?
    @State private var remove: LoggedExercise?
    @State private var guide: ExercisePlan?
    @State private var notes = ""
    @State private var markFeedback = 0
    @State private var requestingPulse = false
    @State private var pulseIssue: String?

    var body: some View {
        NavigationStack {
            if let draft = store.journal.activeWorkout {
                let next = draft.nextStep
                Page {
                    PageHeader(title: draft.name, caption: "Тренировка в процессе") { EmptyView() }
                    stopwatch(draft)
                    if draft.exercises.isEmpty {
                        HintPanel(icon: "dumbbell", title: "Пока нет упражнений", text: "Добавьте упражнение, чтобы записать подходы, повторы и вес.")
                    }
                    LazyVStack(alignment: .leading, spacing: Theme.Space.md) {
                        ForEach(draft.sections) { section in
                            if let block = section.block {
                                blockPanel(section, block: block, next: next?.id)
                            } else if let exercise = section.exercises.first {
                                exercisePanel(exercise, next: next?.id)
                            }
                        }
                    }
                    if !draft.exercises.isEmpty {
                        ActionButton(title: "Добавить упражнение", icon: "plus", solid: false) { adding = true }
                    }
                    pulseDetails(draft)
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
                .safeAreaInset(edge: .bottom, spacing: 0) { controls(draft, next: next) }
                .sensoryFeedback(.selection, trigger: markFeedback)
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
                    SetEditor(selection: picked, remove: {
                        _ = store.removeWorkoutSet(exerciseID: picked.exerciseID, setID: picked.id)
                    }) { value, weight in
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
                .alert("Пульс с Apple Watch", isPresented: Binding(get: { pulseIssue != nil }, set: { if !$0 { pulseIssue = nil } })) {
                    Button("Понятно", role: .cancel) { pulseIssue = nil }
                } message: { Text(pulseIssue ?? "") }
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
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Theme.Space.md) {
                        elapsed(draft)
                        Spacer(minLength: Theme.Space.xs)
                        completed(draft)
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.md) {
                        elapsed(draft)
                        completed(draft)
                    }
                }
                if draft.total > 0 {
                    SwiftUI.ProgressView(value: Double(draft.marked), total: Double(draft.total))
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func elapsed(_ draft: ActiveWorkout) -> some View {
        TimelineView(.periodic(from: draft.startedAt, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(draft.startedAt)))
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Время").font(.subheadline).foregroundStyle(Theme.secondary)
                Text(Format.clock(seconds)).font(Theme.timer).fixedSize()
                    .accessibilityLabel(Format.spokenTime(seconds))
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func completed(_ draft: ActiveWorkout) -> some View {
        let hasDrops = draft.exercises.contains { $0.plan.drops?.isEmpty == false }
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(hasDrops ? "Этапы" : "Подходы").font(.subheadline).foregroundStyle(Theme.secondary)
            Text("\(draft.marked) / \(draft.total)").font(Theme.timer).fixedSize()
                .foregroundStyle(accent)
                .contentTransition(.numericText(value: Double(draft.marked)))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: draft.marked)
                .accessibilityLabel("\(draft.marked) из \(draft.total)")
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func pulseDetails(_ draft: ActiveWorkout) -> some View {
        if let pulse = draft.pulse, let last = pulse.last {
            TimelineView(.periodic(from: .now, by: 10)) { context in
                DisclosureGroup {
                    PulsePanel(points: pulse, live: true, now: context.date).padding(.top, Theme.Space.sm)
                } label: {
                    Label(context.date.timeIntervalSince(last.date) < 30 ? "Пульс: \(last.bpm) уд/мин" : "Пульс за тренировку",
                          systemImage: "heart")
                        .font(.subheadline.weight(.semibold)).frame(minHeight: Theme.touch)
                }
            }
        } else if health.isAvailable && store.journal.healthEnabled {
            HintPanel(icon: "heart", title: "Пульс во время занятия", text: "Для живых замеров откройте «Ритм» на Apple Watch. Замеры из Apple «Здоровья» появятся здесь автоматически.")
        }
    }

    private func exercisePanel(_ exercise: LoggedExercise, next: UUID?) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.plan.name).font(Theme.sectionTitle).accessibilityAddTraits(.isHeader)
                        Text("\(Set(exercise.steps.map(\.round)).count) × \(exercise.plan.target) \(exercise.plan.unit.short)")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    exerciseMenu(exercise)
                }
                ForEach(exercise.steps) { step in
                    stepRow(step, grouped: false, next: next == step.id)
                }
                if exercise.sets.isEmpty {
                    Button("Добавить подход", systemImage: "plus") { appendSet(exercise.id) }
                        .frame(minHeight: Theme.touch)
                }
            }
        }
    }

    private func blockPanel(_ section: WorkoutSection, block: ExerciseBlock, next: UUID?) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Label(block.kind.title, systemImage: block.kind.icon).font(Theme.sectionTitle)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Menu {
                        ForEach(section.exercises) { exercise in
                            Menu(exercise.plan.name) {
                                Button("Мышцы и техника", systemImage: "figure.strengthtraining.traditional") { guide = exercise.plan }
                                Button("Добавить подход", systemImage: "plus") { appendSet(exercise.id) }
                                Button("Удалить упражнение", systemImage: "trash", role: .destructive) { remove = exercise }
                            }
                        }
                    } label: {
                        Image(systemName: "figure.strengthtraining.traditional").frame(width: Theme.touch, height: Theme.touch)
                    }
                    .accessibilityLabel("Техника упражнений")
                }
                ForEach(section.rounds) { round in
                    Text("Раунд \(round.id)").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                    ForEach(round.steps) { step in stepRow(step, grouped: true, next: next == step.id) }
                }
            }
        }
    }

    private func exerciseMenu(_ exercise: LoggedExercise) -> some View {
        Menu {
            Button("Мышцы и техника", systemImage: "figure.strengthtraining.traditional") { guide = exercise.plan }
            Button("Добавить подход", systemImage: "plus") {
                appendSet(exercise.id)
            }
            Button("Удалить упражнение", systemImage: "trash", role: .destructive) { remove = exercise }
        } label: {
            Image(systemName: "ellipsis").frame(width: Theme.touch, height: Theme.touch)
        }
        .accessibilityLabel("Действия: \(exercise.plan.name)")
    }

    private func stepRow(_ step: WorkoutStep, grouped: Bool, next: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            stepControls(step, grouped: grouped, next: next)
            if next, let previous = previousSet(for: step) {
                SetSuggestionButton(previous: previous, unit: step.unit,
                                  matches: step.set.value == previous.value && step.set.weight == previous.weight) {
                    store.applyPreviousSet(previous, to: step)
                }
            }
            if next, let workout = store.journal.activeWorkout,
               let goal = NextExerciseGoal.find(for: step, in: workout, records: store.journal.records) {
                SetSuggestionButton(previous: goal, unit: step.unit,
                                    matches: step.set.value == goal.value && step.set.weight == goal.weight,
                                    title: "Следующая цель", icon: "target") {
                    store.applyPreviousSet(goal, to: step)
                }
            }
        }
        .padding(.leading, step.set.dropStage == nil ? Theme.Space.sm : Theme.Space.lg)
        .padding(.trailing, Theme.Space.xs)
        .padding(.vertical, Theme.Space.xs)
        .background(next ? accent.opacity(0.07) : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .strokeBorder(next ? accent : Theme.border, lineWidth: next ? 2 : 1)
                .allowsHitTesting(false)
        }
        .contextMenu {
            Button(step.set.dropStage == nil ? "Удалить подход с дропами" : "Удалить этап", systemImage: "trash", role: .destructive) {
                _ = store.removeWorkoutSet(exerciseID: step.exerciseID, setID: step.id)
            }
        }
        .accessibilityAction(named: "Удалить подход") {
            _ = store.removeWorkoutSet(exerciseID: step.exerciseID, setID: step.id)
        }
    }

    private func stepControls(_ step: WorkoutStep, grouped: Bool, next: Bool) -> some View {
        let set = step.set
        let quantity = "\(set.value) \(step.unit.short)"
        let weight = set.weight > 0 ? "\(Format.weight(set.weight)) кг" : ""
        let summary = [quantity, weight].filter { !$0.isEmpty }.joined(separator: " · ")
        let repetitions = step.unit == .repetitions
        let label = grouped && set.dropStage == nil ? step.name : step.title
        let stepName = spokenName(step)
        let stacked = repetitions && dynamicTypeSize >= .xxxLarge
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 6))
        return layout {
            Button {
                editing = SetSelection(exerciseID: step.exerciseID, index: step.round, unit: step.unit, set: set,
                                       previous: previousSet(for: step))
            } label: {
                HStack(spacing: 5) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(set.dropStage != nil && grouped ? step.name + " · " + label : label)
                            .font(.subheadline.weight(next ? .semibold : .medium))
                            .foregroundStyle(Theme.primary)
                        if !repetitions || !weight.isEmpty {
                            Text(repetitions ? weight : summary).font(.subheadline.weight(.medium)).monospacedDigit()
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "pencil").font(.caption).foregroundStyle(Theme.secondary)
                }
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, minHeight: Theme.touch, alignment: .leading)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Изменить: \(stepName), \(step.name), \(summary)")
            .accessibilityIdentifier("workout.set.edit")
            HStack(spacing: 6) {
                if repetitions {
                    RepetitionControl(value: set.value, context: "\(step.name), \(stepName)") { change in
                        adjustRepetitions(step, by: change)
                    } count: {
                        Text("\(set.value)")
                            .font(Theme.number).foregroundStyle(Theme.primary)
                            .frame(minWidth: 30)
                            .contentTransition(.numericText(value: Double(set.value)))
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: set.value)
                            .accessibilityLabel(quantity)
                    }
                }
                Button {
                    toggle(step)
                } label: {
                    Image(systemName: set.complete ? "checkmark.circle.fill" : "circle")
                        .font(.title2).foregroundStyle(set.complete ? accent : Theme.secondary)
                        .frame(width: Theme.touch, height: Theme.touch)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel((set.complete ? "Снять отметку: " : "Отметить: ") + stepName + ", " + step.name)
                .accessibilityHint(next ? "Следующий этап тренировки" : "")
                .frame(maxWidth: stacked ? .infinity : nil, alignment: .trailing)
            }
        }
    }

    private func previousSet(for step: WorkoutStep) -> PreviousSet? {
        guard !step.set.complete, let workout = store.journal.activeWorkout else { return nil }
        return PreviousSet.find(for: step, in: workout, records: store.journal.records)
    }

    private func spokenName(_ step: WorkoutStep) -> String {
        step.set.dropStage.map { "подход \(step.round), дроп \($0)" } ?? step.title.lowercased()
    }

    private func toggle(_ step: WorkoutStep) {
        store.toggleSet(exerciseID: step.exerciseID, setID: step.id)
        if !step.set.complete,
           store.journal.activeWorkout?.exercises.first(where: { $0.id == step.exerciseID })?
            .sets.first(where: { $0.id == step.id })?.complete == true {
            markFeedback += 1
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

    private func controls(_ draft: ActiveWorkout, next: WorkoutStep?) -> some View {
        ActionDock {
            if let removed = store.removedWorkoutSets, removed.workoutID == draft.id {
                HStack {
                    Label("Подход удалён", systemImage: "trash").font(.caption).foregroundStyle(Theme.secondary)
                    Spacer(minLength: 8)
                    Button("Вернуть") { _ = store.restoreWorkoutSets(removed) }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: Theme.touch)
                        .accessibilityIdentifier("workout.set.undo")
                }
            }
            if store.journal.healthEnabled { livePulse(draft) }
            if let rest = draft.restUntil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = draft.secondsLeft(at: context.date)
                    VStack(spacing: Theme.Space.sm) {
                        if seconds > 0 {
                            restControl(seconds).accessibilitySortPriority(1)
                            finishButton(draft, solid: false)
                        } else {
                            workoutActions(draft, next: next)
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
                .id(rest)
            } else {
                workoutActions(draft, next: next)
            }
        }
    }

    private func appendSet(_ exerciseID: UUID) {
        store.updateWorkout { draft in
            guard let index = draft.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
            draft.exercises[index].appendRound()
        }
    }

    private func livePulse(_ draft: ActiveWorkout) -> some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let last = draft.pulse?.last
            let live = last.map { context.date.timeIntervalSince($0.date) < 30 } ?? false
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.sm))
                : AnyLayout(HStackLayout(spacing: Theme.Space.sm))
            layout {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: "heart.fill").foregroundStyle(Theme.reference).accessibilityHidden(true)
                    Text(last.map { String($0.bpm) } ?? "—").font(.title3.bold().monospacedDigit())
                        .contentTransition(.numericText())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("уд/мин").font(.caption)
                        Text(live ? "Сейчас" : last.map { "Замер в \($0.date.formatted(.dateTime.hour().minute()))" } ?? "Ждём замер")
                            .font(.caption2).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !live {
                    Button {
                        requestingPulse = true
                        Task {
                            pulseIssue = await health.startWatchPulse(draft.kind)
                            requestingPulse = false
                        }
                    } label: {
                        if requestingPulse { ProgressView() } else { Image(systemName: "applewatch.radiowaves.left.and.right") }
                    }
                    .buttonStyle(.bordered).frame(minWidth: Theme.touch, minHeight: Theme.touch)
                    .disabled(requestingPulse).accessibilityLabel("Включить пульс на Apple Watch")
                }
            }
            .privacySensitive().accessibilityElement(children: .contain)
            .accessibilityIdentifier("workout.pulse")
        }
    }

    @ViewBuilder private func workoutActions(_ draft: ActiveWorkout, next: WorkoutStep?) -> some View {
        if let next {
            VStack(alignment: .leading, spacing: 2) {
                Text(next.name).font(.subheadline)
                Text(next.title).font(.caption)
            }
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            ActionButton(title: next.set.dropStage == nil ? "Отметить подход" : "Отметить этап", icon: "checkmark") {
                guard store.journal.activeWorkout?.nextStep?.id == next.id else { return }
                toggle(next)
            }
            .accessibilityHint("\(next.name), \(spokenName(next)), \(next.set.value) \(next.unit.short)")
            if draft.marked > 0 { finishButton(draft, solid: false) }
        } else if draft.exercises.isEmpty {
            ActionButton(title: "Добавить упражнение", icon: "plus") { adding = true }
        } else {
            finishButton(draft, solid: true)
        }
    }

    private func restControl(_ seconds: Int) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.xs))
            : AnyLayout(HStackLayout(spacing: Theme.Space.sm))
        return layout {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Label("Отдых", systemImage: "timer").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.warning)
                Text(Format.clock(seconds)).font(Theme.timer)
                    .accessibilityLabel(Format.spokenTime(seconds))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button("Пропустить отдых") { store.updateWorkout { $0.restUntil = nil; $0.restOriginSetID = nil } }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(minHeight: Theme.touch)
        }
        .padding(Theme.Space.sm)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
    }

    private func finishButton(_ draft: ActiveWorkout, solid: Bool) -> some View {
        ActionButton(title: "Завершить тренировку", icon: "stop.fill", solid: solid) {
            if draft.marked < draft.total { confirmFinish = true } else { finish() }
        }
        .disabled(draft.marked == 0)
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
    let previous: PreviousSet?
}

private struct SetSuggestionButton: View {
    @Environment(\.ritmAccent) private var accent
    let previous: PreviousSet
    let unit: ExerciseUnit
    let matches: Bool
    var title = "В прошлый раз"
    var icon = "clock.arrow.circlepath"
    let apply: () -> Void

    var body: some View {
        let amount = "\(previous.value) \(unit.short)"
        let details = previous.weight > 0 ? "\(Format.weight(previous.weight)) кг × \(amount)" : amount
        let label = HStack(spacing: Theme.Space.sm) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(Theme.secondary)
                    Text(details).font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(Theme.primary)
                }
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: icon).foregroundStyle(Theme.secondary).accessibilityHidden(true)
            }
            Spacer(minLength: Theme.Space.xs)
            Image(systemName: matches ? "checkmark" : "arrow.turn.down.left")
                .foregroundStyle(matches ? Theme.secondary : accent)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, Theme.Space.xs)
        .frame(minHeight: Theme.touch)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.control))

        if matches {
            label.accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title), \(details)")
                .accessibilityValue("Значения уже в подходе")
        } else {
            Button(action: apply) { label }
                .buttonStyle(PressStyle())
                .accessibilityLabel("\(title), подставить \(details)")
        }
    }
}

private struct SetEditor: View {
    let selection: SetSelection
    let remove: (() -> Void)?
    let save: (Int, Double) -> Void
    @State private var value: String
    @State private var weight: String
    @Environment(\.dismiss) private var dismiss

    init(selection: SetSelection, remove: (() -> Void)? = nil, save: @escaping (Int, Double) -> Void) {
        self.selection = selection
        self.remove = remove
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
                if !exerciseQuantityRange.contains(Int(value.trimmed) ?? 0) {
                    StatusMessage(text: "Укажите число от 1 до 3600.")
                }
                if validWeight(weight) == nil {
                    StatusMessage(text: "Укажите вес от 0 до 500 кг.")
                }
                if let previous = selection.previous {
                    SetSuggestionButton(previous: previous, unit: selection.unit,
                                      matches: Int(value.trimmed) == previous.value && validWeight(weight) == previous.weight) {
                        value = String(previous.value)
                        weight = previous.weight > 0 ? Format.weight(previous.weight) : ""
                    }
                }
                if let remove {
                    Section {
                        Button(selection.set.dropStage == nil ? "Удалить подход" : "Удалить этап", systemImage: "trash", role: .destructive) {
                            remove(); dismiss()
                        }.accessibilityIdentifier("workout.set.delete")
                    } footer: {
                        Text(selection.set.dropStage == nil ? "Основной подход удаляется вместе с его дропами. После удаления доступна кнопка «Вернуть»." : "Удаляется только этот этап. Основной подход сохранится.")
                    }
                }
            }
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
