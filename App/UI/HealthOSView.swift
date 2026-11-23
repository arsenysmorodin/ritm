import SwiftUI

struct InstrumentStrip: View {
    @Environment(\.ritmAccent) private var accent
    var value: Double
    var total: Double
    var body: some View {
        let progress = total > 0 ? min(max(value / total, 0), 1) : 0
        HStack(spacing: 3) {
            ForEach(0..<24) { index in
                let amount = min(max(progress * 24 - Double(index), 0), 1)
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 1).fill(Theme.border.opacity(0.65))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1).fill(accent).frame(width: proxy.size.width * amount)
                        }
                }
            }
        }.frame(height: 14).accessibilityHidden(true)
    }
}

struct WaterInstrument: View {
    let store: HealthOSStore
    var compact = false
    @Environment(\.ritmAccent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settings = false
    @State private var custom = false
    @State private var lastAdded: UUID?
    @State private var feedback = 0
    private var water: Double { store.total(.water) }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("Вода сегодня", systemImage: "drop.fill").font(.headline)
                    Spacer()
                    Button { settings = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                        .accessibilityLabel("Цель и порции воды")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) { waterValue; goal }
                    VStack(alignment: .leading, spacing: 4) { waterValue; goal }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Вода сегодня: \(HealthEvent.number(water)) из \(store.settings.waterGoal) миллилитров")
                .accessibilityIdentifier("water.total")
                .accessibilityValue(HealthEvent.number(water))
                InstrumentStrip(value: water, total: Double(store.settings.waterGoal))
                let columns = typeSize.isAccessibilitySize ? 1 : min(store.settings.waterPortions.count, 3)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: columns), spacing: 8) {
                    ForEach(Array(store.settings.waterPortions.enumerated()), id: \.offset) { _, portion in
                        Button {
                            if store.addWater(portion) {
                                lastAdded = store.events.first { $0.kind == .water && $0.isLocal }?.id
                                feedback += 1
                            }
                        } label: {
                            Text("+\(portion) мл").font(.subheadline.weight(.semibold)).monospacedDigit()
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(PressStyle()).accessibilityLabel("Добавить \(portion) миллилитров воды")
                            .accessibilityIdentifier("water.add.\(portion)")
                    }
                }
                let actionLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())
                actionLayout {
                    Button("Другой объём") { custom = true }.frame(minHeight: 44)
                    if !typeSize.isAccessibilitySize { Spacer() }
                    if let id = lastAdded, let event = store.events.first(where: { $0.id == id }) {
                        Button("Отменить") { store.delete(event); lastAdded = nil }.frame(minHeight: 44)
                    }
                }.font(.subheadline)
                if !compact {
                    Text("Личная цель. Учтены записи «Ритма» и доступные записи воды из «Здоровья».")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
                if let error = store.error { Text(error).font(.subheadline).foregroundStyle(Theme.warning) }
            }
        }
        .sheet(isPresented: $settings) { HealthOSSettingsView(store: store) }
        .sheet(isPresented: $custom) { HealthEventEditor(store: store, kind: .water) }
        .sensoryFeedback(.selection, trigger: feedback)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: water)
    }
    private var waterValue: some View {
        Text(HealthEvent.number(water)).font(.system(.largeTitle, design: .monospaced, weight: .medium))
            .fontWidth(.expanded).foregroundStyle(accent).contentTransition(.numericText())
    }
    private var goal: some View { Text("/ \(store.settings.waterGoal) мл").font(.subheadline).foregroundStyle(Theme.secondary) }
}

struct HealthOSHome: View {
    let store: HealthOSStore
    let journal: JournalStore
    let bridge: HealthOSBridge
    @State private var entry: HealthEventKind?
    var body: some View {
        if store.isReadable {
            MorningBrief(store: store)
            DailyResourcePanel(store: store)
            WaterInstrument(store: store)
            VStack(spacing: 0) {
                NavigationLink { SupplementsView(store: store) } label: {
                    HealthRouteRow(title: "Добавки", subtitle: supplementStatus, icon: "pills")
                }.accessibilityIdentifier("health.supplements")
                Divider().overlay(Theme.border)
                NavigationLink { DayTimelineView(store: store, journal: journal) } label: {
                    HealthRouteRow(title: "Лента дня", subtitle: "Привычки, питание и тренировки", icon: "point.3.connected.trianglepath.dotted")
                }.accessibilityIdentifier("health.timeline")
                Divider().overlay(Theme.border)
                NavigationLink { HealthInsightsView(store: store, journal: journal) } label: {
                    HealthRouteRow(title: "Закономерности", subtitle: "История и сравнение периодов", icon: "chart.xyaxis.line")
                }.accessibilityIdentifier("health.insights")
                Divider().overlay(Theme.border)
                NavigationLink { ExperimentsView(store: store) } label: {
                    HealthRouteRow(title: "Эксперименты", subtitle: "Проверяйте по одной привычке", icon: "flask")
                }.accessibilityIdentifier("health.experiments")
            }.buttonStyle(PressStyle())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138))], spacing: 8) {
                ForEach([HealthEventKind.caffeine, .meal, .checkIn, .context, .measurement]) { kind in
                    Button { entry = kind } label: {
                        Label(kind.title, systemImage: kind.icon).font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 50).padding(.horizontal, 8)
                            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(PressStyle())
                }
            }
            if bridge.busy { StatusMessage(text: "Обновляем историю здоровья…", loading: true) }
            if let issue = bridge.issue { StatusMessage(text: issue) }
            if journal.journal.healthEnabled {
                Button("Доступ к воде, кофеину и дневному свету") {
                    Task { await bridge.authorize(journal, daily: store) }
                }.font(.subheadline).frame(minHeight: 44).disabled(bridge.busy)
            }
        } else {
            HintPanel(icon: "externaldrive.badge.exclamationmark", title: "Health OS недоступен",
                      text: store.error ?? "Откройте приложение ещё раз. Журнал тренировок доступен отдельно.")
            Button("Повторить") { store.reload() }.frame(minHeight: 44)
        }
        // A zero-height anchor keeps the presentation attached when the content changes.
        Color.clear.frame(height: 0)
            .sheet(item: $entry) { kind in HealthEventEditor(store: store, kind: kind) }
    }
    private var supplementStatus: String {
        let today = Date.now
        let slots = store.supplements.flatMap { supplement in supplement.slots(on: today).map { (supplement, $0) } }
        let completed = slots.filter { HealthOSLogic.completedSlot($0.1, supplement: $0.0.id, events: store.events) }.count
        return slots.isEmpty ? "Свой состав и расписание приёма" : "Отмечено \(completed) из \(slots.count) приёмов сегодня"
    }
}

struct HealthRouteRow: View {
    let title: String
    let subtitle: String
    let icon: String
    @Environment(\.ritmAccent) private var accent
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(accent).frame(width: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(Theme.primary)
                Text(subtitle).font(.subheadline).foregroundStyle(Theme.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.secondary).accessibilityHidden(true)
        }.padding(.vertical, 14).contentShape(Rectangle())
    }
}

struct MorningBrief: View {
    let store: HealthOSStore
    var body: some View {
        let latest = store.days.last { $0.values[.sleepMinutes] != nil }
        if let latest, Date.now.timeIntervalSince(latest.date) < 3 * 86400 {
            VStack(alignment: .leading, spacing: 12) {
                Text("После сна").font(Theme.sectionTitle).accessibilityAddTraits(.isHeader)
                Text(Format.date(latest.date)).font(.caption).foregroundStyle(Theme.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) { values(latest) }
                    VStack(alignment: .leading, spacing: 12) { values(latest) }
                }
                if let sleepStart = latest.sleepStart,
                   let coffee = store.events.first(where: { $0.kind == .caffeine && $0.date <= sleepStart && sleepStart.timeIntervalSince($0.date) < 24 * 3600 }) {
                    Text("Последний кофеин — за \(HealthEvent.number(sleepStart.timeIntervalSince(coffee.date) / 3600)) ч до сна.")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                }
                if let sleepStart = latest.sleepStart,
                   let meal = store.events.first(where: { $0.kind == .meal && $0.date <= sleepStart && sleepStart.timeIntervalSince($0.date) < 18 * 3600 }) {
                    Text("Последняя еда — за \(HealthEvent.number(sleepStart.timeIntervalSince(meal.date) / 3600)) ч до сна.")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                }
            }.padding(.vertical, 6)
        }
    }
    @ViewBuilder private func values(_ day: DailyHealth) -> some View {
        if let sleep = day.values[.sleepMinutes] { MetricValue(title: "Сон", value: "\(Int(sleep) / 60) ч \(Int(sleep) % 60) м") }
        if let hrv = day.values[.hrv] { MetricValue(title: "ВСР · SDNN", value: "\(HealthEvent.number(hrv)) мс", prominence: true) }
    }
}

struct DayTimelineView: View {
    let store: HealthOSStore
    let journal: JournalStore
    @State private var day = Date.now
    @State private var entry: HealthEventKind?
    @State private var editing: HealthEvent?
    @State private var kind: HealthEventKind?
    var body: some View {
        Page {
            DatePicker("День", selection: $day, in: ...Date.now, displayedComponents: .date).datePickerStyle(.compact)
            ScrollView(.horizontal) {
                HStack {
                    filter("Все", selection: nil)
                    ForEach(HealthEventKind.allCases) { filter($0.title, selection: $0) }
                }
            }.scrollIndicators(.hidden)
            let logs = HealthOSLogic.events(store.events, on: day, kind: kind)
            let workouts = journal.journal.records.filter { Calendar.current.isDate($0.startedAt, inSameDayAs: day) }
            let timeline: [DayTimelineItem] = (logs.map { .event($0) } + (kind == nil ? workouts.map { .workout($0) } : [])).sorted { $0.date > $1.date }
            if timeline.isEmpty {
                HintPanel(icon: "list.bullet", title: "В этот день нет записей", text: "Добавьте воду, приём пищи или самочувствие. Записи из «Здоровья» появятся после предоставления доступа.")
            }
            ForEach(timeline) { item in
                switch item {
                case .event(let event):
                    HealthEventRow(event: event)
                        .contextMenu {
                            if event.isLocal {
                                Button("Изменить", systemImage: "pencil") { editing = event }
                                Button("Удалить", systemImage: "trash", role: .destructive) { store.delete(event) }
                            } else { Text("Изменение в исходном приложении") }
                        }
                case .workout(let workout):
                    HStack(spacing: 14) {
                        Image(systemName: "dumbbell").frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.name).font(.headline)
                            Text(workout.startedAt, style: .time).font(.caption).foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
            Menu {
                ForEach(HealthEventKind.allCases.filter { ![.supplement, .experiment].contains($0) }) { item in
                    Button(item.title, systemImage: item.icon) { entry = item }
                }
            } label: { Label("Добавить запись", systemImage: "plus.circle.fill").frame(maxWidth: .infinity, minHeight: 52) }
        }
        .navigationTitle("Лента дня").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $entry) { HealthEventEditor(store: store, kind: $0, initialDate: day) }
        .sheet(item: $editing) { HealthEventEditor(store: store, kind: $0.kind, editing: $0) }
    }
    private func filter(_ title: String, selection: HealthEventKind?) -> some View {
        Button { kind = selection } label: {
            Text(title).font(.subheadline).padding(.horizontal, 14).frame(minHeight: 44)
                .background(kind == selection ? Theme.elevated : Theme.surface, in: Capsule())
        }.buttonStyle(PressStyle()).accessibilityAddTraits(kind == selection ? .isSelected : [])
    }
}

private enum DayTimelineItem: Identifiable {
    case event(HealthEvent), workout(WorkoutRecord)
    var id: String {
        switch self { case .event(let event): "event.\(event.id)"; case .workout(let record): "workout.\(record.id)" }
    }
    var date: Date {
        switch self { case .event(let event): event.date; case .workout(let record): record.startedAt }
    }
}

struct HealthEventRow: View {
    let event: HealthEvent
    @Environment(\.ritmAccent) private var accent
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: event.kind.icon).foregroundStyle(accent).frame(width: 28, height: 28)
                Rectangle().fill(Theme.border).frame(width: 1, height: 24)
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.title.isEmpty ? event.kind.title : event.title).font(.headline)
                    Spacer(minLength: 8)
                    Text(event.date, style: .time).font(.caption).monospacedDigit().foregroundStyle(Theme.secondary)
                }
                if !event.summary.isEmpty { Text(event.summary).font(Theme.number) }
                if event.kind == .checkIn {
                    Text(event.ratings.keys.sorted().map { "\(ratingTitle($0)): \(event.ratings[$0] ?? 0)/5" }.joined(separator: ", "))
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                }
                if !event.note.isEmpty, event.note != event.summary { Text(event.note).font(.subheadline).foregroundStyle(Theme.secondary) }
                Text(event.source).font(.caption).foregroundStyle(Theme.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
}

func ratingTitle(_ key: String) -> String {
    ["energy": "Энергия", "stress": "Стресс", "sleepiness": "Сонливость", "soreness": "Боль в мышцах", "digestion": "Комфорт ЖКТ"][key] ?? key
}
