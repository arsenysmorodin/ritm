import SwiftUI
#if os(iOS)
import WidgetKit
#endif

struct TrainingHomeView: View {
    @Environment(\.ritmAccent) private var accent
    let store: JournalStore
    var start: (Routine?) -> Void
    var programs: () -> Void
    var openHistory: () -> Void
    var openRecord: (UUID) -> Void
    var openAppearance: () -> Void = {}
    var now = Date.now
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        let journal = store.journal
        let suggestion = journal.suggestion(on: now)
        Page {
            PageHeader(title: "Тренировки", caption: "Движение как часть вашего дня") {
                Button(action: openAppearance) { IconBadge(icon: "gearshape") }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Настройки")
            }

            workoutPanel(journal.activeWorkout, suggestion, program: journal.activeProgram?.name)
            let navigationLayout = textSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            navigationLayout {
                ActionButton(title: "Программы", icon: "square.stack", solid: false, action: programs)
                    .accessibilityIdentifier("training.programs")
                ActionButton(title: "История", icon: "clock.arrow.circlepath", solid: false, action: openHistory)
                    .accessibilityIdentifier("training.history")
            }
            if journal.activeWorkout == nil, suggestion != nil {
                Button {
                    start(nil)
                } label: {
                    Label("Свободная тренировка", systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: Theme.touch, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }

            weekPanel(journal.week(containing: now), goal: journal.weeklyGoal)

            if let latest = journal.records.first {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            SectionHeading(title: "Последняя тренировка")
                            Spacer(minLength: Theme.Space.sm)
                            allHistory
                        }.fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            SectionHeading(title: "Последняя тренировка")
                            allHistory
                        }
                    }
                    Button { openRecord(latest.id) } label: { RecordRow(record: latest) }
                        .buttonStyle(PressStyle())
                }
            } else if suggestion == nil {
                ActionButton(title: "Составить программу", icon: "square.stack", solid: false, action: programs)
            }
        }
    }

    private var allHistory: some View {
        Button("Вся история", action: openHistory)
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: Theme.touch)
    }

    private func workoutPanel(_ draft: ActiveWorkout?, _ routine: Routine?, program: String?) -> some View {
        let title = draft?.name ?? routine?.name ?? "Свободная тренировка"
        let kind = draft?.kind ?? routine?.kind ?? .strength
        let plannedToday = routine?.weekday?.rawValue == Calendar.current.component(.weekday, from: now)

        return Panel {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Label(draft != nil ? "В процессе" : plannedToday ? "По плану на сегодня" : "Тренировка",
                          systemImage: draft != nil ? "play.circle.fill" : kind.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(draft != nil ? accent : Theme.secondary)
                    Text(title).font(Theme.screenTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let draft {
                        let hasDrops = draft.exercises.contains { $0.plan.drops?.isEmpty == false }
                        Text("\(draft.marked) из \(draft.total) \(hasDrops ? "этапов" : "подходов")")
                            .font(Theme.number)
                        if draft.total > 0 {
                            SwiftUI.ProgressView(value: Double(draft.marked), total: Double(draft.total))
                                .accessibilityHidden(true)
                        }
                    } else if let routine {
                        Text([Format.exercises(routine.exercises.count), Format.sets(routine.setCount)].joined(separator: "  ·  "))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.primary)
                        if let program {
                            Text(program).font(.subheadline).foregroundStyle(Theme.secondary)
                        }
                    } else {
                        Text("Добавляйте упражнения по ходу занятия.").font(.subheadline).foregroundStyle(Theme.secondary)
                    }
                }
                ActionButton(title: draft == nil ? "Начать тренировку" : "Продолжить тренировку",
                             icon: "play.fill") { start(routine) }
            }
        }
    }

    private func weekPanel(_ week: [TrainingDay], goal: Int) -> some View {
        let total = week.reduce(0) { $0 + $1.count }
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Space.xs), count: textSize.isAccessibilitySize ? 4 : 7)
        return Panel {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                MetricValue(title: "Тренировки за неделю", value: "\(total) из \(goal)", prominence: total > 0)
                LazyVGrid(columns: columns, spacing: Theme.Space.sm) {
                    ForEach(week) { day in
                        VStack(spacing: Theme.Space.xs) {
                            Text(day.weekday.short).font(.caption.weight(day.isToday ? .bold : .medium))
                                .foregroundStyle(day.isToday ? Theme.primary : Theme.secondary)
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(day.count > 0 ? accent : Theme.elevated)
                                    .overlay {
                                        if day.isToday {
                                            RoundedRectangle(cornerRadius: 6)
                                                .strokeBorder(day.count > 0 ? Theme.onAccent : accent, lineWidth: 2)
                                        }
                                    }
                                if day.count > 0 {
                                    Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(Theme.onAccent)
                                } else if day.planned {
                                    Circle().fill(Theme.secondary).frame(width: 5, height: 5)
                                }
                            }.frame(height: 26)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(day.weekday.short), \(day.isToday ? "сегодня, " : "")\(day.count > 0 ? Format.workouts(day.count) : day.planned ? "по плану" : "свободно")")
                    }
                }
            }
        }
    }
}

struct AppearanceSettings: View {
    let store: JournalStore
    @Environment(HealthOSStore.self) private var daily
    @Environment(HealthOSBridge.self) private var bridge
    @Environment(\.dismiss) private var dismiss
    @AppStorage(RitmAppearance.key) private var appearance = RitmAppearance.system
    @AppStorage(RitmAccent.appKey) private var appAccent = RitmAccent.lime
    @AppStorage(RitmAccent.widgetKey, store: WidgetStorage.preferences) private var widgetAccent = RitmAccent.lime
    @State private var showWaterSettings = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Приложение") {
                    Picker("Тема", selection: $appearance) {
                        ForEach(RitmAppearance.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    accentPicker("Акцент приложения", selection: $appAccent, options: RitmAccent.appOptions)
                }
                Section("Виджеты") {
                    accentPicker("Цвет виджетов", selection: $widgetAccent, options: RitmAccent.allCases)
                        #if os(iOS)
                        .pickerStyle(.navigationLink)
                        #endif
                }
                Section("Данные") {
                    NavigationLink("Резервная копия") { BackupView(store: store) }
                    Button("Вода и напоминания") { showWaterSettings = true }
                    if store.journal.healthEnabled {
                        Button(daily.settings.writeIntakeToHealth ? "Обновить доступ к записи воды и кофеина" : "Сохранять воду и кофеин в «Здоровье»") {
                            Task { await bridge.authorize(store, daily: daily, write: true) }
                        }.disabled(bridge.busy)
                        if daily.settings.writeIntakeToHealth {
                            Button("Остановить запись воды и кофеина") {
                                var settings = daily.settings; settings.writeIntakeToHealth = false
                                _ = daily.saveSettings(settings)
                            }
                        }
                        Button("Обновить историю здоровья за год") {
                            Task { await bridge.refresh(store, daily: daily, force: true, fullHistory: true) }
                        }.disabled(bridge.busy)
                    }
                    if let message = daily.importMessage { Text(message).font(.caption).foregroundStyle(Theme.secondary) }
                    if let issue = bridge.issue { Text(issue).font(.caption).foregroundStyle(Theme.warning) }
                }
            }
            .navigationTitle("Настройки")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .sheet(isPresented: $showWaterSettings) { HealthOSSettingsView(store: daily) }
        #if os(iOS)
        .onChange(of: widgetAccent) { _, _ in WidgetCenter.shared.reloadAllTimelines() }
        #endif
    }

    private func accentPicker(_ title: String, selection: Binding<RitmAccent>, options: [RitmAccent]) -> some View {
        Picker(title, selection: selection) {
            ForEach(options) { option in
                Label {
                    Text(option.title)
                } icon: {
                    Circle().fill(option.color).frame(width: 14, height: 14).accessibilityHidden(true)
                }
                .tag(option)
            }
        }
    }
}
