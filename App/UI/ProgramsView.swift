import SwiftUI

struct ProgramsView: View {
    let store: JournalStore
    let start: (Routine?) -> Void
    @State private var editing: Program?
    @State private var deleting: Program?
    @State private var selected: Routine?
    @State private var pendingStart: Routine?
    @State private var showCatalog = false

    var body: some View {
        Page {
            PageHeader(title: "Программы", caption: "Ваш план занятий дома") {
                Button { editing = Program(name: "", routines: []) } label: {
                    IconBadge(icon: "plus", size: 46)
                }.buttonStyle(PressStyle()).accessibilityLabel("Создать программу")
            }
            ActionButton(title: "Каталог упражнений", icon: "figure.strengthtraining.traditional", solid: false) { showCatalog = true }
            if store.journal.programs.isEmpty {
                HintPanel(icon: "square.stack", title: "Пока без программы", text: "Соберите тренировки и выберите дни, в которые хотите заниматься.")
                ActionButton(title: "Создать программу", icon: "plus") { editing = Program(name: "", routines: []) }
            }
            ForEach(store.journal.programs) { program in
                let active = store.journal.activeProgramID == program.id
                Panel {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(program.name).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                                if active {
                                    Label("Активная программа", systemImage: "checkmark.circle.fill")
                                        .font(.caption.weight(.semibold)).foregroundStyle(Ink.lilac)
                                } else {
                                    Text(Format.workouts(program.routines.count)).font(.caption).foregroundStyle(Ink.muted)
                                }
                            }
                            Spacer(minLength: 5)
                            #if RITM_PREVIEW
                            menuIcon
                            #else
                            Menu {
                                Button("Редактировать", systemImage: "pencil") { editing = program }
                                if !active {
                                    Button("Сделать активной", systemImage: "checkmark.circle") {
                                        store.change { $0.activeProgramID = program.id }
                                    }
                                }
                                Button("Удалить программу", systemImage: "trash", role: .destructive) { deleting = program }
                            } label: {
                                menuIcon
                            }.accessibilityLabel("Действия программы \(program.name)")
                            #endif
                        }
                        ForEach(program.routines) { routine in
                            Button { selected = routine } label: { RoutineRow(routine: routine) }.buttonStyle(PressStyle())
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showCatalog) { NavigationStack { ExerciseLibraryView() } }
        .sheet(item: $editing) { program in
            ProgramEditor(initial: program) { store.save($0) }
        }
        .sheet(item: $selected, onDismiss: {
            if let pendingStart {
                self.pendingStart = nil
                start(pendingStart)
            }
        }) { routine in
            NavigationStack {
                Page {
                    PageHeader(title: routine.name, caption: routine.kind.title) { IconBadge(icon: routine.kind.icon, color: routine.kind.color) }
                    Panel {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeading(title: "Упражнения")
                            ForEach(routine.exercises) { item in
                                if item.id != routine.exercises.first?.id { Divider() }
                                NavigationLink {
                                    ExercisePlanDetailView(plan: item)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.name).font(.headline)
                                            Text(planSummary(item, in: routine))
                                                .font(.subheadline).foregroundStyle(Ink.muted)
                                        }
                                        Spacer(minLength: 6)
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ink.lilac)
                                    }
                                }
                                .buttonStyle(PressStyle())
                            }
                        }
                    }
                    MuscleMap(muscles: .combined(routine.exercises.map(\.muscles)), title: "Мышцы тренировочного дня")
                    ActionButton(title: store.journal.activeWorkout == nil ? "Начать тренировку" : "Продолжить текущую", icon: "play.fill", color: Ink.peach) {
                        pendingStart = routine
                        selected = nil
                    }
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { selected = nil } } }
            }
        }
        .alert("Удалить программу?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { program in
            Button("Удалить", role: .destructive) { store.deleteProgram(program.id); deleting = nil }
            Button("Отмена", role: .cancel) { deleting = nil }
        } message: { _ in Text("Записи о выполненных тренировках останутся в истории.") }
    }
    private var menuIcon: some View {
        Image(systemName: "ellipsis").font(.headline).foregroundStyle(Ink.lilac)
            .frame(width: 44, height: 44)
            .background(Ink.raised, in: RoundedRectangle(cornerRadius: 12))
    }
}

private func planSummary(_ exercise: ExercisePlan, in routine: Routine) -> String {
    var details = ["\(exercise.sets) × \(exercise.target) \(exercise.unit.short)"]
    if exercise.weight > 0 { details.append("\(Format.weight(exercise.weight)) кг") }
    if let block = routine.exerciseBlocks.first(where: { $0.exerciseIDs.contains(exercise.id) }) { details.append(block.kind.title) }
    if !(exercise.drops ?? []).isEmpty { details.append("Дропсет") }
    return details.joined(separator: " · ")
}

struct RoutineRow: View {
    let routine: Routine
    var body: some View {
        HStack(spacing: 11) {
            IconBadge(icon: routine.kind.icon, color: routine.kind.color, size: 39)
            VStack(alignment: .leading, spacing: 3) {
                Text(routine.name).font(.subheadline.weight(.semibold))
                Text([routine.weekday?.short, Format.exercises(routine.exercises.count)].compactMap { $0 }.joined(separator: " • "))
                    .font(.caption).foregroundStyle(Ink.muted)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Ink.muted)
        }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.raised, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
    }
}

struct ProgramEditor: View {
    @State private var draft: Program
    @State private var routine: Routine?
    @Environment(\.dismiss) private var dismiss
    let save: (Program) -> Bool

    init(initial: Program, save: @escaping (Program) -> Bool) {
        _draft = State(initialValue: initial)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Программа") { TextField("Название программы", text: $draft.name).editAutocorrection() }
                Section("Тренировки") {
                    ForEach(draft.routines) { item in
                        Button { routine = item } label: { RoutineRow(routine: item) }.buttonStyle(PressStyle())
                    }
                    .onDelete { draft.routines.remove(atOffsets: $0) }
                    .onMove { draft.routines.move(fromOffsets: $0, toOffset: $1) }
                    Button("Добавить тренировку", systemImage: "plus") { routine = Routine(name: "") }
                }
            }
            .formTint()
            .navigationTitle("Программа")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        draft.name = draft.name.trimmed
                        if save(draft) { dismiss() }
                    }.disabled(draft.name.trimmed.isEmpty || draft.routines.isEmpty)
                }
                #if os(iOS)
                ToolbarItem(placement: .bottomBar) { if !draft.routines.isEmpty { EditButton() } }
                #endif
            }
            .sheet(item: $routine) { item in
                RoutineEditor(initial: item) { edited in
                    if let index = draft.routines.firstIndex(where: { $0.id == edited.id }) { draft.routines[index] = edited }
                    else { draft.routines.append(edited) }
                }
            }
        }
    }
}

struct RoutineEditor: View {
    @State private var draft: Routine
    @State private var exercise: ExercisePlan?
    @State private var block: ExerciseBlock?
    @Environment(\.dismiss) private var dismiss
    let save: (Routine) -> Void

    init(initial: Routine, save: @escaping (Routine) -> Void) {
        _draft = State(initialValue: initial)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Тренировка") {
                    TextField("Название тренировки", text: $draft.name).editAutocorrection()
                    Picker("Тип", selection: $draft.kind) {
                        ForEach(WorkoutKind.allCases) { kind in Text(kind.title).tag(kind) }
                    }
                    Picker("День недели", selection: $draft.weekday) {
                        Text("Любой день").tag(nil as Weekday?)
                        ForEach(Weekday.allCases) { day in Text(day.short).tag(Optional(day)) }
                    }
                }
                Section("Упражнения") {
                    ForEach(draft.exercises) { item in
                        Button { exercise = item } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name).foregroundStyle(Ink.primary)
                                    Text(planSummary(item, in: draft)).font(.caption).foregroundStyle(Ink.muted)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ink.muted)
                            }
                        }.buttonStyle(PressStyle())
                    }
                    .onDelete { draft.removeExercises(at: $0) }
                    .onMove { draft.exercises.move(fromOffsets: $0, toOffset: $1) }
                    Button("Добавить упражнение", systemImage: "plus") { exercise = ExercisePlan(name: "") }
                }
                Section {
                    ForEach(draft.exerciseBlocks) { item in
                        Button { block = item } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(item.kind.title, systemImage: item.kind.icon).foregroundStyle(Ink.primary)
                                Text(draft.exercises.filter { item.exerciseIDs.contains($0.id) }.map(\.name).joined(separator: " · "))
                                    .font(.caption).foregroundStyle(Ink.muted)
                            }
                        }
                    }
                    .onDelete(perform: removeBlocks)
                    Button("Добавить суперсет или круг", systemImage: "link") {
                        block = ExerciseBlock(kind: .superset, exerciseIDs: [])
                    }
                    .disabled(availableExercises(for: nil).count < 2)
                } header: {
                    Text("Суперсеты и круги")
                } footer: {
                    Text("Порядок внутри группы совпадает со списком упражнений. Таймер отдыха запускается после раунда.")
                }
                MuscleMap(muscles: .combined(draft.exercises.map(\.muscles)), title: "Мышцы тренировочного дня")
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            .formTint()
            .navigationTitle("Тренировка")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { draft.name = draft.name.trimmed; save(draft); dismiss() }
                        .disabled(draft.name.trimmed.isEmpty || draft.exercises.isEmpty)
                }
                #if os(iOS)
                ToolbarItem(placement: .bottomBar) { if !draft.exercises.isEmpty { EditButton() } }
                #endif
            }
            .sheet(item: $exercise) { item in
                let grouped = draft.exerciseBlocks.contains { $0.exerciseIDs.contains(item.id) }
                ExerciseEditor(initial: item, fixedSets: grouped) { updated in
                    if let index = draft.exercises.firstIndex(where: { $0.id == updated.id }) { draft.exercises[index] = updated }
                    else { draft.exercises.append(updated) }
                }
            }
            .sheet(item: $block) { item in
                ExerciseBlockEditor(initial: item, exercises: availableExercises(for: item)) { edited, rounds in
                    draft.save(edited, rounds: rounds)
                }
            }
        }
    }

    private func availableExercises(for block: ExerciseBlock?) -> [ExercisePlan] {
        let used = Set(draft.exerciseBlocks.filter { $0.id != block?.id }.flatMap(\.exerciseIDs))
        return draft.exercises.filter { !used.contains($0.id) }
    }

    private func removeBlocks(at offsets: IndexSet) {
        var blocks = draft.exerciseBlocks
        blocks.remove(atOffsets: offsets)
        draft.blocks = blocks
    }
}

private struct ExerciseBlockEditor: View {
    @State private var draft: ExerciseBlock
    @State private var rounds: Int
    @Environment(\.dismiss) private var dismiss
    let exercises: [ExercisePlan]
    let save: (ExerciseBlock, Int) -> Void

    init(initial: ExerciseBlock, exercises: [ExercisePlan], save: @escaping (ExerciseBlock, Int) -> Void) {
        _draft = State(initialValue: initial)
        _rounds = State(initialValue: exercises.first { initial.exerciseIDs.contains($0.id) }?.sets ?? 3)
        self.exercises = exercises
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Формат", selection: $draft.kind) {
                        ForEach(ExerciseBlockKind.allCases) { kind in
                            Text(kind == .circuit ? "Круговая серия" : kind.title).tag(kind)
                        }
                    }
                    Stepper("Раунды: \(rounds)", value: $rounds, in: 1...20)
                    Stepper("Отдых после раунда: \(draft.rest) сек", value: $draft.rest, in: 0...300, step: 15)
                }
                Section {
                    ForEach(exercises) { exercise in
                        let included = draft.exerciseIDs.contains(exercise.id)
                        Toggle(exercise.name, isOn: Binding(get: { draft.exerciseIDs.contains(exercise.id) }, set: { enabled in
                            if enabled { draft.exerciseIDs.append(exercise.id) }
                            else { draft.exerciseIDs.removeAll { $0 == exercise.id } }
                        }))
                        .disabled(!included && draft.kind == .superset && draft.exerciseIDs.count >= 2)
                    }
                } header: {
                    Text("Упражнения")
                } footer: {
                    Text(draft.kind == .superset ? "Выберите два упражнения." : "Выберите минимум три упражнения.")
                }
            }
            .formTint()
            .navigationTitle("Суперсет или круг")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { save(draft, rounds); dismiss() }
                        .disabled(!draft.kind.accepts(draft.exerciseIDs.count))
                }
            }
        }
    }
}

struct ExerciseEditor: View {
    @State private var draft: ExercisePlan
    @State private var weight: String
    @State private var target: String
    @State private var drops: [DropInput]
    @State private var showCatalog = false
    @Environment(\.dismiss) private var dismiss
    private let fixedSets: Bool
    let save: (ExercisePlan) -> Void

    init(initial: ExercisePlan, fixedSets: Bool = false, save: @escaping (ExercisePlan) -> Void) {
        var draft = initial
        if initial.name.isEmpty { draft.isCustom = true }
        _draft = State(initialValue: draft)
        _target = State(initialValue: String(initial.target))
        _weight = State(initialValue: initial.weight > 0 ? Format.weight(initial.weight) : "")
        _drops = State(initialValue: (initial.drops ?? []).map(DropInput.init))
        self.fixedSets = fixedSets
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Упражнение") {
                    TextField("Например, приседания", text: $draft.name).editAutocorrection()
                    Button("Выбрать из каталога", systemImage: "figure.strengthtraining.traditional") { showCatalog = true }
                    ExerciseReferenceLinks(
                        plan: draft,
                        selection: Binding(get: { draft.muscles }, set: { draft.muscleOverride = $0 })
                    )
                    Picker("Как считать", selection: $draft.unit) {
                        ForEach(ExerciseUnit.allCases) { unit in Text(unit.label).tag(unit) }
                    }
                }
                if draft.isCustom == true {
                    Section("Техника") {
                        TextField("Ваша заметка о движении", text: Binding(
                            get: { draft.techniqueNote ?? "" },
                            set: { draft.techniqueNote = $0 }
                        ), axis: .vertical).lineLimit(2...5).editAutocorrection()
                    }
                }
                Section("Нагрузка") {
                    if fixedSets {
                        Text(Format.sets(draft.sets) + " по раундам")
                    } else {
                        Stepper("Подходы: \(draft.sets)", value: $draft.sets, in: 1...20)
                    }
                    if draft.unit == .repetitions {
                        RepetitionField(text: $target)
                    } else {
                        HStack {
                            Text(draft.unit.label)
                            Spacer()
                            TextField("Цель", text: $target)
                                .numericKeyboard().multilineTextAlignment(.trailing).frame(minWidth: 75).accessibilityLabel(draft.unit.label)
                        }
                    }
                    HStack {
                        Text("Вес, кг")
                        Spacer()
                        TextField("Без веса", text: $weight).numericKeyboard(decimal: true)
                            .multilineTextAlignment(.trailing).frame(minWidth: 75).accessibilityLabel("Вес в килограммах")
                    }
                    if !fixedSets {
                        Stepper(draft.rest == 0 ? "Без таймера отдыха" : "Отдых: \(draft.rest) сек", value: $draft.rest, in: 0...300, step: 15)
                    }
                }
                if draft.unit == .repetitions && ((kilograms ?? 0) > 0 || !drops.isEmpty) { dropSection }
            }
            .formTint()
            .navigationTitle("Упражнение")
            .sheet(isPresented: $showCatalog) {
                NavigationStack {
                    ExerciseLibraryView { entry in
                        draft.catalogID = entry.id
                        draft.isCustom = false
                        draft.muscleOverride = nil
                        draft.name = entry.name
                        draft.unit = entry.unit
                        target = String(entry.target)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        guard let kilograms, let validatedTarget, let validatedDrops else { return }
                        draft.name = draft.name.trimmed
                        draft.weight = kilograms
                        draft.target = validatedTarget
                        draft.drops = validatedDrops.isEmpty ? nil : validatedDrops
                        draft.techniqueNote = draft.techniqueNote?.trimmed
                        save(draft)
                        dismiss()
                    }.disabled(draft.name.trimmed.isEmpty || validatedTarget == nil || kilograms == nil || validatedDrops == nil)
                }
            }
        }
    }

    private var kilograms: Double? { validWeight(weight) }
    private var validatedTarget: Int? {
        guard let number = Int(target.trimmed), exerciseQuantityRange.contains(number) else { return nil }
        return number
    }

    private var dropSection: some View {
        Section {
            ForEach($drops) { $drop in
                let id = drop.id
                let number = (drops.firstIndex { $0.id == id } ?? 0) + 1
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Этап \(number)").font(.caption.weight(.semibold)).foregroundStyle(Ink.lilac)
                        Spacer()
                        Button(role: .destructive) { drops.removeAll { $0.id == id } } label: {
                            Image(systemName: "trash").frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Удалить этап \(number)")
                    }
                    RepetitionField(text: $drop.repetitions, label: "Повторы, этап \(number)")
                    HStack {
                        Text("Вес, кг")
                        Spacer()
                        TextField("0", text: $drop.weight).numericKeyboard(decimal: true)
                            .multilineTextAlignment(.trailing).frame(minWidth: 75).accessibilityLabel("Вес, этап \(number)")
                    }
                }
            }
            if drops.count < 4 {
                Button("Добавить этап снижения веса", systemImage: "minus.circle") {
                    let previous = drops.last.flatMap { validWeight($0.weight) } ?? kilograms ?? 0
                    let next = ((previous * 0.75) * 10).rounded(.down) / 10
                    drops.append(DropInput(repetitions: String(validatedTarget ?? 10), weight: Format.weight(next)))
                }.disabled((drops.last.flatMap { validWeight($0.weight) } ?? kilograms ?? 0) <= 0)
            }
        } header: {
            Text("Дропсет")
        } footer: {
            Text(validatedDrops == nil ? "Укажите повторы и вес ниже предыдущего на каждом этапе." : "После основного подхода сразу переходите к следующему весу.")
                .foregroundStyle(validatedDrops == nil ? Ink.peach : Ink.muted)
        }
    }

    private var validatedDrops: [DropStagePlan]? {
        if draft.unit != .repetitions { return [] }
        var stages: [DropStagePlan] = []
        var previous = kilograms ?? 0
        for drop in drops {
            guard let repetitions = Int(drop.repetitions.trimmed), exerciseQuantityRange.contains(repetitions),
                  let weight = validWeight(drop.weight), weight < previous else { return nil }
            stages.append(DropStagePlan(repetitions: repetitions, weight: weight))
            previous = weight
        }
        return stages
    }
}

private struct DropInput: Identifiable {
    let id = UUID()
    var repetitions: String
    var weight: String

    init(repetitions: String, weight: String) {
        self.repetitions = repetitions
        self.weight = weight
    }

    init(_ stage: DropStagePlan) {
        repetitions = String(stage.repetitions)
        weight = Format.weight(stage.weight)
    }
}

private struct ExerciseReferenceLinks: View {
    let plan: ExercisePlan
    @Binding var selection: MuscleSelection

    var body: some View {
        NavigationLink {
            MuscleEditor(selection: $selection)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Группы мышц")
                let names = (selection.primary + selection.secondary).map(\.title)
                if !names.isEmpty {
                    Text(names.joined(separator: ", "))
                        .font(.caption).foregroundStyle(Ink.muted).lineLimit(2)
                }
            }
        }
        if !plan.name.trimmed.isEmpty {
            NavigationLink("Мышцы и техника") { ExercisePlanDetailView(plan: plan) }
        }
    }
}

private struct MuscleEditor: View {
    @Binding var selection: MuscleSelection

    private enum Role: String, CaseIterable { case none = "Не выбрана", primary = "Основная", secondary = "Дополнительная" }

    var body: some View {
        Form {
            MuscleMap(muscles: selection)
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section("Группы мышц") {
                ForEach(Muscle.allCases) { muscle in
                    Picker(muscle.title, selection: role(for: muscle)) {
                        ForEach(Role.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
            }
        }
        .formTint()
        .navigationTitle("Группы мышц")
    }

    private func role(for muscle: Muscle) -> Binding<Role> {
        Binding {
            if selection.primary.contains(muscle) { return .primary }
            if selection.secondary.contains(muscle) { return .secondary }
            return .none
        } set: { role in
            var updated = selection
            updated.primary.removeAll { $0 == muscle }
            updated.secondary.removeAll { $0 == muscle }
            if role == .primary { updated.primary.append(muscle) }
            if role == .secondary { updated.secondary.append(muscle) }
            selection = updated
        }
    }
}

func validWeight(_ text: String) -> Double? {
    if text.trimmed.isEmpty { return 0 }
    guard let number = Double(text.trimmed.replacingOccurrences(of: ",", with: ".")), (0...500).contains(number) else { return nil }
    return number
}
