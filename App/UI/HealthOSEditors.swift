import SwiftUI

struct HealthEventEditor: View {
    let store: HealthOSStore
    let kind: HealthEventKind
    var editing: HealthEvent?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HealthEvent
    @State private var amount: Double
    @State private var amountText: String

    init(store: HealthOSStore, kind: HealthEventKind, editing: HealthEvent? = nil, initialDate: Date = .now) {
        self.store = store; self.kind = kind; self.editing = editing
        var event = editing ?? HealthEvent(kind: kind, date: min(initialDate, .now), title: kind.title)
        if kind == .checkIn && event.ratings.isEmpty { event.ratings = ["energy": 3, "stress": 3, "sleepiness": 3, "soreness": 1, "digestion": 3] }
        if kind == .measurement && editing == nil { event.title = ""; event.unit = "" }
        if kind == .context && editing == nil { event.title = "Изменение режима" }
        _draft = State(initialValue: event)
        let initialAmount = event.amount ?? (kind == .water ? 250 : kind == .caffeine ? 80 : 1)
        _amount = State(initialValue: initialAmount)
        _amountText = State(initialValue: HealthQuantityInput.editingString(initialAmount))
    }

    var body: some View {
        NavigationStack {
            Form {
                if kind == .water || kind == .caffeine || kind == .measurement {
                    Section(kind == .water ? "Объём, мл" : kind == .caffeine ? "Кофеин, мг" : "Значение") {
                        HStack {
                            Button { adjustAmount(-(kind == .water ? 50 : 10)) } label: {
                                Image(systemName: "minus").frame(width: 44, height: 44)
                            }.buttonStyle(.borderless).accessibilityLabel("Уменьшить количество")
                            TextField("Количество", text: $amountText)
                                .keyboardType(.decimalPad).font(.system(.largeTitle, design: .monospaced)).multilineTextAlignment(.center)
                                .accessibilityLabel("Количество")
                                .accessibilityIdentifier("event.amount")
                            Button { adjustAmount(kind == .water ? 50 : 10) } label: {
                                Image(systemName: "plus").frame(width: 44, height: 44)
                            }.buttonStyle(.borderless).accessibilityLabel("Увеличить количество")
                        }
                        Button("Очистить количество") { amountText = "" }
                            .frame(minHeight: 44).accessibilityIdentifier("event.clearAmount")
                    }
                }
                if kind == .caffeine {
                    Section {
                        TextField("Напиток или продукт", text: $draft.title)
                        Text("Введите кофеин с упаковки или по данным заведения. Количество в одинаковых напитках может различаться.")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
                if kind == .meal {
                    Section {
                        TextField("Например, ужин", text: $draft.title)
                        Text("Эта запись отмечает время еды. Калории, БЖУ и клетчатка продолжают поступать из «Здоровья», в том числе через FatSecret.")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
                if kind == .checkIn {
                    Section("Ощущения от 1 до 5") {
                        ForEach(["energy", "stress", "sleepiness", "soreness", "digestion"], id: \.self) { key in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(ratingTitle(key)).font(.headline)
                                Picker(ratingTitle(key), selection: Binding(get: { draft.ratings[key] ?? 3 }, set: { draft.ratings[key] = $0 })) {
                                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                                }.pickerStyle(.segmented)
                            }.padding(.vertical, 6)
                        }
                    }
                    Section { Text("Энергия и комфорт ЖКТ: 5 — высокий уровень. Стресс, сонливость и боль: 5 — выраженные ощущения.").font(.caption).foregroundStyle(Theme.secondary) }
                }
                if kind == .context {
                    Section("Что изменилось") {
                        Picker("Событие", selection: $draft.title) {
                            ForEach(["Изменение режима", "Болезнь", "Поездка", "Смена часового пояса", "Алкоголь", "Дневной сон", "Новый режим питания", "Новый режим сна"], id: \.self) { Text($0) }
                        }
                    }
                }
                if kind == .measurement {
                    Section("Показатель") {
                        TextField("Название, например окружность талии", text: $draft.title)
                        TextField("Единица, например см или ммоль/л", text: $draft.unit)
                        Text("Референсный интервал лаборатории и условия измерения можно указать в заметке. Приложение сохраняет ваши измерения без медицинской интерпретации.")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
                if kind == .supplement {
                    Section {
                        Text(draft.title)
                        Stepper("\(HealthEvent.number(amount)) порц.", value: $amount, in: 0.5...20, step: 0.5)
                        Toggle("Пропущено", isOn: $draft.skipped)
                    }
                }
                Section {
                    DatePicker("Когда", selection: $draft.date, in: ...Date.now)
                    TextField("Заметка", text: $draft.note, axis: .vertical).lineLimit(2...5)
                }
                if let error = store.error { Text(error).foregroundStyle(Theme.warning) }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(editing == nil ? kind.title : "Изменить запись")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }.fontWeight(.semibold).accessibilityIdentifier("event.save")
                }
            }
            .alert("Запись не сохранена", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("ОК") { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
    }
    private func save() {
        draft.updatedAt = .now
        draft.timezone = TimeZone.current.identifier; draft.offsetSeconds = TimeZone.current.secondsFromGMT(for: draft.date)
        if [.water, .caffeine, .measurement].contains(kind) {
            guard let value = HealthQuantityInput.parse(amountText) else { store.error = "Введите количество числом."; return }
            draft.amount = value
        } else if kind == .supplement { draft.amount = amount }
        if kind == .water { draft.unit = "мл" }
        if kind == .caffeine { draft.unit = "мг" }
        draft.needsHealthSync = [.water, .caffeine].contains(kind)
        guard !draft.title.trimmingCharacters(in: .whitespaces).isEmpty else { store.error = "Укажите название."; return }
        if store.log(draft) { dismiss() }
    }
    private func adjustAmount(_ delta: Double) {
        amount = max(kind == .water ? 10 : 1, (HealthQuantityInput.parse(amountText) ?? amount) + delta)
        amountText = HealthQuantityInput.editingString(amount)
    }
}

struct SupplementsView: View {
    let store: HealthOSStore
    @State private var editing: Supplement?
    @State private var adding = false
    @State private var day = Date.now
    var body: some View {
        Page {
            DatePicker("День приёма", selection: $day, in: ...Date.now, displayedComponents: .date)
            if store.supplements.isEmpty {
                HintPanel(icon: "pills", title: "Ваши добавки", text: "Добавьте продукт, состав на порцию и расписание. Суммарный состав за день учитывает только принятые порции.")
            }
            ForEach(store.supplements) { supplement in
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(supplement.name).font(.title3.weight(.semibold))
                                Text("\(HealthEvent.number(supplement.servings)) × \(supplement.portion)").font(.subheadline).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Menu {
                                Button("Изменить", systemImage: "pencil") { editing = supplement }
                                Button("Завершить курс", systemImage: "archivebox") { store.archiveSupplement(supplement) }
                            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Настройки \(supplement.name)")
                        }
                        ForEach(supplement.slots(on: day), id: \.self) { slot in
                            let event = store.events.first { $0.linkedID == supplement.id && $0.scheduledAt == slot && $0.kind == .supplement }
                            if let event {
                                Label {
                                    Text("\(slot.formatted(date: .omitted, time: .shortened)) · \(event.skipped ? "пропущено" : "принято в " + event.date.formatted(date: .omitted, time: .shortened))")
                                } icon: { Image(systemName: event.skipped ? "minus.circle" : "checkmark.circle.fill") }
                                .font(.subheadline).frame(minHeight: 44)
                                .contextMenu { Button("Отменить отметку", systemImage: "arrow.uturn.backward") { store.delete(event) } }
                            } else {
                                ViewThatFits(in: .horizontal) {
                                    HStack { slotActions(supplement, slot: slot) }
                                    VStack(alignment: .leading) { slotActions(supplement, slot: slot) }
                                }
                            }
                        }
                        if supplement.slots(on: day).isEmpty { Text("На этот день приём не запланирован.").font(.subheadline).foregroundStyle(Theme.secondary) }
                    }
                }
            }
            let totals = HealthOSLogic.ingredientTotals(store.events, on: day)
            if !totals.isEmpty {
                SectionHeading(title: "Суммарно за день")
                ForEach(totals) { item in
                    HStack {
                        Text(item.name)
                        Spacer()
                        Text("\(HealthEvent.number(item.amount)) \(item.unit.rawValue)").monospacedDigit().fontWeight(.semibold)
                    }.accessibilityElement(children: .combine)
                }
                Text("Суммируются ингредиенты с одинаковым названием и единицей. Указывайте активное вещество, например магний, и количество с этикетки.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
            ActionButton(title: "Добавить продукт", icon: "plus") { adding = true }
        }
        .navigationTitle("Добавки").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) { SupplementEditor(store: store, supplement: Supplement()) }
        .sheet(item: $editing) { SupplementEditor(store: store, supplement: $0) }
    }
    @ViewBuilder private func slotActions(_ supplement: Supplement, slot: Date) -> some View {
        Button {
            _ = store.take(supplement, slot: slot, at: Calendar.current.isDateInToday(day) ? .now : slot)
        } label: { Label("Принять · \(slot.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark").frame(minHeight: 48) }
            .buttonStyle(.borderedProminent)
        Button("Пропустить") { _ = store.take(supplement, slot: slot, skipped: true, at: Calendar.current.isDateInToday(day) ? .now : slot) }.frame(minHeight: 44)
    }
}

struct SupplementEditor: View {
    let store: HealthOSStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Supplement
    @State private var courseEnd: Bool
    init(store: HealthOSStore, supplement: Supplement) {
        self.store = store; _draft = State(initialValue: supplement); _courseEnd = State(initialValue: supplement.endsAt != nil)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Продукт и порция") {
                    TextField("Название", text: $draft.name).accessibilityIdentifier("supplement.name")
                    TextField("Единица порции: капсула, ложка…", text: $draft.portion)
                    Stepper("За приём: \(HealthEvent.number(draft.servings)) порц.", value: $draft.servings, in: 0.5...20, step: 0.5)
                }
                Section {
                    ForEach($draft.ingredients) { $ingredient in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Активное вещество", text: $ingredient.name)
                            HStack {
                                TextField("Количество", value: $ingredient.amount, format: .number).keyboardType(.decimalPad)
                                    .accessibilityLabel("Количество \(ingredient.name) на порцию")
                                Picker("Единица", selection: $ingredient.unit) {
                                    ForEach(IngredientUnit.allCases) { Text($0.rawValue).tag($0) }
                                }
                            }
                        }
                    }.onDelete { draft.ingredients.remove(atOffsets: $0) }
                    Button("Добавить ингредиент", systemImage: "plus") { draft.ingredients.append(SupplementIngredient()) }.frame(minHeight: 44)
                } header: { Text("Состав на одну порцию") } footer: { Text("Используйте количество активного вещества с этикетки. Дозировки приложение не назначает.") }
                Section("Расписание") {
                    ForEach(Array(draft.times.indices), id: \.self) { index in
                        DatePicker("Приём \(index + 1)", selection: Binding(get: { date(draft.times[index]) }, set: {
                            let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                            draft.times[index] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                        }), displayedComponents: .hourAndMinute)
                    }.onDelete { if draft.times.count > $0.count { draft.times.remove(atOffsets: $0) } }
                    if draft.times.count < 6 { Button("Добавить время") { draft.times.append(1080) }.frame(minHeight: 44) }
                    ForEach(Weekday.allCases) { weekday in
                        Toggle(weekday.short, isOn: Binding(get: { draft.weekdays.contains(weekday.rawValue) }, set: { selected in
                            if selected { draft.weekdays.append(weekday.rawValue) } else { draft.weekdays.removeAll { $0 == weekday.rawValue } }
                        }))
                    }
                }
                Section("Курс") {
                    DatePicker("С", selection: $draft.startsAt, displayedComponents: .date)
                    Toggle("Дата окончания", isOn: $courseEnd)
                    if courseEnd {
                        DatePicker("По", selection: Binding(get: { draft.endsAt ?? draft.startsAt }, set: { draft.endsAt = $0 }), in: draft.startsAt..., displayedComponents: .date)
                    }
                    TextField("Заметка", text: $draft.notes, axis: .vertical)
                }
                if let error = store.error { Text(error).foregroundStyle(Theme.warning) }
            }
            .navigationTitle("Добавка").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        draft.times = Array(Set(draft.times)).sorted()
                        if !courseEnd { draft.endsAt = nil } else if draft.endsAt == nil { draft.endsAt = draft.startsAt }
                        if store.saveSupplement(draft) { dismiss() }
                    }
                }
            }
        }
    }
    private func date(_ minute: Int) -> Date { Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now }
}

struct HealthOSSettingsView: View {
    let store: HealthOSStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HealthOSSettings
    @State private var notificationIssue: String?
    init(store: HealthOSStore) { self.store = store; _draft = State(initialValue: store.settings) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Цель: \(draft.waterGoal) мл", value: $draft.waterGoal, in: 100...10000, step: 100)
                    ForEach(draft.waterPortions.indices, id: \.self) { index in
                        Stepper("Порция \(index + 1): \(draft.waterPortions[index]) мл", value: $draft.waterPortions[index], in: 10...5000, step: 10)
                    }
                } header: { Text("Вода") } footer: { Text("Настройте собственную цель. Приложение не оценивает обезвоживание и не учитывает автоматически воду в пище.") }
                Section("Напоминания") {
                    Toggle("О воде днём", isOn: Binding(get: { !draft.waterReminderTimes.isEmpty }, set: { draft.waterReminderTimes = $0 ? [660, 840, 1020] : [] }))
                    ForEach(draft.waterReminderTimes.indices, id: \.self) { index in
                        DatePicker("Вода \(index + 1)", selection: Binding(get: { minuteDate(draft.waterReminderTimes[index]) }, set: { draft.waterReminderTimes[index] = minuteValue($0) }), displayedComponents: .hourAndMinute)
                    }
                    Toggle("О добавках по расписанию", isOn: $draft.supplementReminders)
                    Text("Уведомления включаются после сохранения настроек. Напоминания об уже отмеченных приёмах отменяются при следующем обновлении приложения.").font(.caption).foregroundStyle(Theme.secondary)
                }
                if let notificationIssue { Text(notificationIssue).foregroundStyle(Theme.warning) }
                if let error = store.error { Text(error).foregroundStyle(Theme.warning) }
            }
            .navigationTitle("Вода и напоминания").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if store.saveSettings(draft) {
                            Task {
                                notificationIssue = await HealthOSNotifications.update(store, requestPermission: true)
                                if notificationIssue == nil { dismiss() }
                            }
                        }
                    }
                }
            }
        }
    }
}

private func minuteDate(_ minute: Int) -> Date { Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now }
private func minuteValue(_ date: Date) -> Int { Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date) }
