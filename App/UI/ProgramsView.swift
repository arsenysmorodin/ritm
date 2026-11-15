import SwiftUI

struct ProgramsView: View {
    let store: JournalStore
    let start: (Routine?) -> Void
    @State private var editing: Program?
    @State private var deleting: Program?
    @State private var selected: Routine?
    @State private var pendingStart: Routine?

    var body: some View {
        Page {
            PageHeader(title: "Программы", caption: "Ваш план занятий дома") {
                Button { editing = Program(name: "", routines: []) } label: {
                    IconBadge(icon: "plus", size: 46)
                }.buttonStyle(PressStyle()).accessibilityLabel("Создать программу")
            }
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
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name).font(.headline)
                                    Text("\(item.sets) × \(item.target) \(item.unit.short)" + (item.weight > 0 ? ", \(Format.weight(item.weight)) кг" : ""))
                                        .font(.subheadline).foregroundStyle(Ink.muted)
                                }
                            }
                        }
                    }
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
                            HStack {
                                Text(item.name).foregroundStyle(Ink.primary)
                                Spacer()
                                Text("\(item.sets) × \(item.target) \(item.unit.short)").font(.caption).foregroundStyle(Ink.muted)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ink.muted)
                            }
                        }.buttonStyle(PressStyle())
                    }
                    .onDelete { draft.exercises.remove(atOffsets: $0) }
                    .onMove { draft.exercises.move(fromOffsets: $0, toOffset: $1) }
                    Button("Добавить упражнение", systemImage: "plus") { exercise = ExercisePlan(name: "") }
                }
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
                ExerciseEditor(initial: item) { updated in
                    if let index = draft.exercises.firstIndex(where: { $0.id == updated.id }) { draft.exercises[index] = updated }
                    else { draft.exercises.append(updated) }
                }
            }
        }
    }
}

struct ExerciseEditor: View {
    @State private var draft: ExercisePlan
    @State private var weight: String
    @State private var target: String
    @Environment(\.dismiss) private var dismiss
    let save: (ExercisePlan) -> Void

    init(initial: ExercisePlan, save: @escaping (ExercisePlan) -> Void) {
        _draft = State(initialValue: initial)
        _target = State(initialValue: String(initial.target))
        _weight = State(initialValue: initial.weight > 0 ? Format.weight(initial.weight) : "")
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Упражнение") {
                    TextField("Например, приседания", text: $draft.name).editAutocorrection()
                    if draft.name.trimmed.isEmpty {
                        Menu("Выбрать из списка") {
                            ForEach(["Приседания", "Отжимания", "Ягодичный мост", "Обратные выпады", "Планка", "Тяга гантелей", "Повороты корпуса"], id: \.self) { name in
                                Button(name) { draft.name = name; if name == "Планка" { draft.unit = .seconds; target = "30" } }
                            }
                        }
                    }
                    Picker("Как считать", selection: $draft.unit) {
                        ForEach(ExerciseUnit.allCases) { unit in Text(unit.label).tag(unit) }
                    }
                }
                Section("Нагрузка") {
                    Stepper(Format.sets(draft.sets), value: $draft.sets, in: 1...20)
                    HStack {
                        Text(draft.unit.label)
                        Spacer()
                        TextField("Цель", text: $target)
                            .numericKeyboard().multilineTextAlignment(.trailing).frame(minWidth: 75).accessibilityLabel(draft.unit.label)
                    }
                    HStack {
                        Text("Вес, кг")
                        Spacer()
                        TextField("Без веса", text: $weight).numericKeyboard(decimal: true)
                            .multilineTextAlignment(.trailing).frame(minWidth: 75).accessibilityLabel("Вес в килограммах")
                    }
                    Stepper(draft.rest == 0 ? "Без таймера отдыха" : "Отдых: \(draft.rest) сек", value: $draft.rest, in: 0...300, step: 15)
                }
            }
            .formTint()
            .navigationTitle("Упражнение")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        guard let kilograms, let validatedTarget else { return }
                        draft.name = draft.name.trimmed
                        draft.weight = kilograms
                        draft.target = validatedTarget
                        save(draft)
                        dismiss()
                    }.disabled(draft.name.trimmed.isEmpty || validatedTarget == nil || kilograms == nil)
                }
            }
        }
    }

    private var kilograms: Double? { validWeight(weight) }
    private var validatedTarget: Int? {
        guard let number = Int(target.trimmed), (1...3600).contains(number) else { return nil }
        return number
    }
}

func validWeight(_ text: String) -> Double? {
    if text.trimmed.isEmpty { return 0 }
    guard let number = Double(text.trimmed.replacingOccurrences(of: ",", with: ".")), (0...500).contains(number) else { return nil }
    return number
}
