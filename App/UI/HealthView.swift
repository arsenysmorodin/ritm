import SwiftUI

struct HealthView: View {
    let store: JournalStore
    let health: HealthConnection
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var showPermissions = false

    var body: some View {
        Page {
            PageHeader(title: "Здоровье", caption: "Активность за сегодня") { IconBadge(icon: "heart", color: Ink.peach) }
            if store.journal.healthEnabled && health.isAvailable {
                let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 9)) : AnyLayout(HStackLayout(spacing: 9))
                layout {
                    metric("Шаги", icon: "figure.walk", value: health.steps, color: Ink.lilac)
                    metric("Активные ккал", icon: "flame", value: health.activeEnergy, color: Ink.peach)
                }
                if health.steps == nil || health.activeEnergy == nil {
                    Text(health.isReading ? "Обновляем данные…" : "Прочерк означает, что за сегодня нет доступных данных.")
                        .font(.footnote).foregroundStyle(Ink.muted)
                }
            }
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "Apple «Здоровье»")
                    Text(connectionText).font(.subheadline).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    if health.isAvailable {
                        if store.journal.healthEnabled {
                            ActionButton(title: "Как изменить разрешения", icon: "gearshape", solid: false) {
                                showPermissions = true
                            }
                            Button("Отключить обмен") { health.disconnect(store) }
                                .font(.subheadline).frame(minHeight: 44).disabled(health.isBusy)
                        } else {
                            ActionButton(title: "Подключить «Здоровье»", icon: "heart") {
                                Task { await health.connect(store) }
                            }.disabled(health.isBusy)
                        }
                    }
                    if let issue = health.issue { Text(issue).font(.footnote).foregroundStyle(Ink.peach) }
                }
            }
            Panel {
                VStack(alignment: .leading, spacing: 5) {
                    SectionHeading(title: "Цель на неделю")
                    Stepper(Format.workouts(store.journal.weeklyGoal), value: Binding(get: { store.journal.weeklyGoal }, set: { goal in
                        store.change { $0.weeklyGoal = goal }
                    }), in: 1...14)
                        .font(.subheadline)
                    Text("Прогресс виден на экране «Сегодня».").font(.footnote).foregroundStyle(Ink.muted)
                }
            }
            Text("Программы и журнал хранятся на этом устройстве.").font(.footnote).foregroundStyle(Ink.muted)
        }
        .task { await health.refresh(store) }
        .refreshable { await health.refresh(store) }
        .alert("Разрешения «Здоровья»", isPresented: $showPermissions) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Откройте приложение Apple «Здоровье», нажмите на фото профиля и в разделе «Конфиденциальность» выберите «Приложения» → «Ритм». Там можно изменить доступ к шагам, активной энергии и записи тренировок.")
        }
    }

    private var connectionText: String {
        if !health.isAvailable { return health.availabilityMessage }
        if !store.journal.healthEnabled { return "Показывает шаги и активную энергию за день. С разрешения сохраняет завершённые тренировки в «Здоровье»." }
        if !health.canWrite { return "Чтобы отправлять тренировки, разрешите «Ритму» запись в Apple «Здоровье»." }
        return "Завершённые тренировки автоматически сохраняются в «Здоровье»."
    }

    private func metric(_ label: String, icon: String, value: Int?, color: Color) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).foregroundStyle(color).accessibilityHidden(true)
                Text(value.map(Format.integer) ?? "—").font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
                Text(label).font(.caption).foregroundStyle(Ink.muted)
            }.accessibilityElement(children: .combine)
        }
    }
}
