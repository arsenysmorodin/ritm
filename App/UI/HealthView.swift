import SwiftUI

struct HealthView: View {
    let store: JournalStore
    let health: HealthConnection
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var showPermissions = false

    var body: some View {
        Page {
            PageHeader(title: "Здоровье", caption: "Активность за сегодня") { EmptyView() }
            if store.journal.healthEnabled && health.isAvailable {
                if health.isReading && health.steps == nil && health.activeEnergy == nil {
                    Panel { StatusMessage(text: "Обновляем активность…", loading: true) }
                } else if health.steps == nil && health.activeEnergy == nil {
                    HintPanel(icon: "figure.walk", title: "Нет данных за сегодня",
                              text: "Активность появится после записи шагов или активной энергии в Apple «Здоровье».")
                } else {
                    let layout = textSize >= .xxxLarge
                        ? AnyLayout(VStackLayout(spacing: Theme.Space.sm)) : AnyLayout(HStackLayout(spacing: Theme.Space.sm))
                    layout {
                        metric("Шаги", icon: "figure.walk", value: health.steps)
                        metric("Активные ккал", icon: "flame", value: health.activeEnergy)
                    }
                }
            }
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "Apple «Здоровье»")
                    if health.isAvailable && store.journal.healthEnabled && health.canWrite {
                        Label("Подключено", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                    }
                    Text(connectionText).font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    if health.isAvailable {
                        if store.journal.healthEnabled {
                            ActionButton(title: "Как изменить разрешения", icon: "gearshape", solid: false) {
                                showPermissions = true
                            }
                            if health.additionalPermissionsPending {
                                ActionButton(title: "Разрешить вес и пульс", icon: "heart.text.square", solid: false) {
                                    Task { await health.connect(store) }
                                }.disabled(health.isBusy)
                            }
                            Button("Отключить обмен") { health.disconnect(store) }
                                .font(.subheadline).frame(minHeight: 44).disabled(health.isBusy)
                        } else {
                            ActionButton(title: "Подключить «Здоровье»", icon: "heart") {
                                Task { await health.connect(store) }
                            }.disabled(health.isBusy)
                        }
                    }
                    if health.isBusy { StatusMessage(text: "Выполняем запрос…", loading: true) }
                    if let issue = health.issue { StatusMessage(text: issue) }
                }
            }
            Panel {
                VStack(alignment: .leading, spacing: 5) {
                    SectionHeading(title: "Цель на неделю")
                    Stepper(Format.workouts(store.journal.weeklyGoal), value: Binding(get: { store.journal.weeklyGoal }, set: { goal in
                        store.change { $0.weeklyGoal = goal }
                    }), in: 1...14)
                        .font(.subheadline)
                    Text("Прогресс виден на экране «Сегодня».").font(.footnote).foregroundStyle(Theme.secondary)
                }
            }
            Text("Программы и журнал хранятся на этом устройстве.").font(.footnote).foregroundStyle(Theme.secondary)
        }
        .task { await health.refresh(store) }
        .refreshable { await health.refresh(store) }
        .alert("Разрешения «Здоровья»", isPresented: $showPermissions) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Откройте приложение Apple «Здоровье», нажмите на фото профиля и в разделе «Конфиденциальность» выберите «Приложения» → «Ритм». Там можно изменить доступ к шагам, активной энергии, весу тела, пульсу и записи тренировок.")
        }
    }

    private var connectionText: String {
        if !health.isAvailable { return health.availabilityMessage }
        if !store.journal.healthEnabled { return "Показывает шаги и активную энергию за день. С разрешения сохраняет завершённые тренировки в «Здоровье»." }
        if !health.canWrite { return "Чтобы отправлять тренировки, разрешите «Ритму» запись в Apple «Здоровье»." }
        return "Завершённые тренировки автоматически сохраняются в «Здоровье»."
    }

    private func metric(_ label: String, icon: String, value: Int?) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Image(systemName: icon).foregroundStyle(Theme.secondary).accessibilityHidden(true)
                if let value {
                    MetricValue(title: label, value: Format.integer(value))
                } else {
                    Text(label).font(.subheadline).foregroundStyle(Theme.secondary)
                    Text("Нет данных").font(.headline)
                }
            }
        }
    }
}
