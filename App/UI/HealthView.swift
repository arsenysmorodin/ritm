import SwiftUI

struct HealthView: View {
    @Environment(\.ritmAccent) private var accent
    let store: JournalStore
    let health: HealthConnection
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var showPermissions = false

    var body: some View {
        Page {
            PageHeader(title: "Здоровье", caption: "Активность и показатели") { EmptyView() }
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
            if store.journal.healthEnabled && health.isAvailable {
                heartPanel(health.widgetSnapshot)
                nutritionPanel(health.widgetSnapshot)
                if let issue = health.widgetError { Panel { StatusMessage(text: issue) } }
            }
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "Apple «Здоровье»")
                    if health.isAvailable && store.journal.healthEnabled && health.canWrite {
                        Label("Подключено", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(accent)
                    }
                    Text(connectionText).font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    if health.isAvailable {
                        if store.journal.healthEnabled {
                            ActionButton(title: "Как изменить разрешения", icon: "gearshape", solid: false) {
                                showPermissions = true
                            }
                            if health.additionalPermissionsPending {
                                ActionButton(title: "Разрешить данные для виджетов", icon: "heart.text.square", solid: false) {
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
            Text("Откройте Apple «Здоровье» → Профиль → Приложения → «Ритм». Разрешите чтение пульса, ВСР и показателей питания, которые хотите видеть в виджетах.")
        }
    }

    private var connectionText: String {
        if !health.isAvailable { return health.availabilityMessage }
        if !store.journal.healthEnabled { return "Показывает пульс, ВСР и питание из FatSecret. С разрешения сохраняет завершённые тренировки в Apple «Здоровье»." }
        if !health.canWrite { return "Чтобы отправлять тренировки, разрешите «Ритму» запись в Apple «Здоровье»." }
        return "Завершённые тренировки автоматически сохраняются в «Здоровье»."
    }

    private func heartPanel(_ snapshot: HealthWidgetSnapshot?) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                SectionHeading(title: "Пульс и ВСР")
                let layout = textSize >= .xxxLarge
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.md))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Space.gutter))
                layout {
                    heartMetric("Пульс", reading: snapshot?.pulse.recent(at: .now), unit: "уд/мин")
                    heartMetric("ВСР (SDNN)", reading: snapshot?.hrv.recent(at: .now), unit: "мс")
                }
                Text("Виджет показывает последние замеры и график за сегодня.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func heartMetric(_ title: String, reading: CardiacReading?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title).font(.subheadline).foregroundStyle(Theme.secondary)
            if let reading {
                Text("\(Format.weight(reading.value)) \(unit)").font(Theme.number)
                Text(reading.date.formatted(.dateTime.day().month().hour().minute().locale(Format.russian)))
                    .font(.caption).foregroundStyle(Theme.secondary)
            } else {
                Text("Нет замеров").font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func nutritionPanel(_ snapshot: HealthWidgetSnapshot?) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                SectionHeading(title: "Питание")
                Text("За сегодня · FatSecret через Apple «Здоровье»")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
                ForEach(Nutrient.allCases, id: \.self) { kind in
                    HStack(alignment: .firstTextBaseline) {
                        Text(kind.title).foregroundStyle(kind == .fiber ? Theme.primary : Theme.secondary)
                        Spacer(minLength: Theme.Space.sm)
                        if let amount = snapshot?.nutrient(kind, at: .now) {
                            Text("\(Format.weight(amount)) \(kind.unit)").fontWeight(.semibold).monospacedDigit()
                                .foregroundStyle(kind == .fiber ? accent : Theme.primary)
                        } else {
                            Text("Нет данных").foregroundStyle(Theme.secondary)
                        }
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
                if snapshot?.nutrient(.fiber, at: .now) == nil {
                    Text("Клетчатка появится, когда FatSecret запишет её в Apple «Здоровье» и «Ритм» получит доступ к чтению.")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                }
            }
        }
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
