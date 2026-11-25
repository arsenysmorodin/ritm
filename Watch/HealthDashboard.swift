import SwiftUI

struct WatchDashboard: View {
    let workout: WatchWorkout
    let health: WatchHealthStore
    let rest: WatchRestAlert
    @Environment(\.scenePhase) private var scene
    @State private var page = 0
    @State private var settings = false

    var body: some View {
        TabView(selection: $page) {
            WatchOverview(health: health, openSettings: { settings = true }).tag(0)
            WatchWellbeing(health: health).tag(1)
            WatchTraining(workout: workout, rest: rest).tag(2)
        }
        .tabViewStyle(.page)
        .background(Theme.background)
        .tint(Theme.accent)
        .modifier(WatchTestDisplay())
        .sheet(isPresented: $settings) { WatchSettings(health: health, rest: rest) }
        .task {
            await workout.recover()
            if workout.context != nil || workout.link.companion != nil { page = 2 }
            #if DEBUG && targetEnvironment(simulator)
            let arguments = ProcessInfo.processInfo.arguments
            if let flag = arguments.firstIndex(of: "--watch-page"), arguments.indices.contains(flag + 1),
               let selected = Int(arguments[flag + 1]), (0...2).contains(selected) { page = selected }
            #endif
            health.refresh()
        }
        .onChange(of: scene, initial: true) { _, value in
            rest.update(workout.link.companion, hasWorkoutSession: workout.context != nil, foreground: value == .active)
            if value == .active { health.refresh() }
        }
        .onChange(of: workout.context?.id) { _, id in if id != nil { page = 2 } }
    }
}

private struct WatchTestDisplay: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--watch-large-text") {
            content.environment(\.dynamicTypeSize, .accessibility1)
        } else { content }
        #else
        content
        #endif
    }
}

struct WatchPage<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .containerRelativeFrame(.horizontal) { width, _ in max(0, width - Theme.Space.sm * 2) }
                .padding(.horizontal, Theme.Space.sm)
                .padding(.bottom, 20)
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Theme.background.ignoresSafeArea() }
        .ignoresSafeArea(.container, edges: .horizontal)
        .foregroundStyle(Theme.primary)
        .tint(Theme.accent)
        .modifier(WatchFlexibleButtons())
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 14).accessibilityHidden(true) }
    }
}

private struct WatchOverview: View {
    let health: WatchHealthStore
    let openSettings: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    private var pair: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .top, spacing: 6))
    }

    var body: some View {
        WatchPage {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("РИТМ").font(.caption2.weight(.bold)).tracking(2).foregroundStyle(Theme.accent)
                    Text("Обзор").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 0)
                Button(action: openSettings) { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("Связь и сигнал отдыха")
            }
            if let data = health.snapshot, data.readable {
                if !data.isToday(at: .now) {
                    Label("Данные за \(data.day.formatted(.dateTime.day().month()))", systemImage: "clock")
                        .font(.caption).foregroundStyle(Theme.warning)
                }
                if data.healthEnabled && data.metrics.isEmpty {
                    Text("Показателей пока нет. Обновите «Ритм» на iPhone и проверьте доступ к «Здоровью».")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
                if let sleep = data.metric(.sleep) {
                    metric(sleep, icon: "moon.zzz.fill", large: true)
                }
                if data.metric(.hrv) != nil || data.metric(.pulse) != nil {
                    pair {
                        if let hrv = data.metric(.hrv) { metric(hrv, icon: "waveform.path.ecg") }
                        if let pulse = data.metric(.pulse) { metric(pulse, icon: "heart.fill") }
                    }
                }
                if data.metric(.steps) != nil || data.metric(.activeEnergy) != nil {
                    pair {
                        if let steps = data.metric(.steps) { metric(steps, icon: "figure.walk") }
                        if let energy = data.metric(.activeEnergy) { metric(energy, icon: "flame.fill") }
                    }
                }
                water(data)
                if data.supplementsPlanned > 0 {
                    watchCard {
                        Label("Добавки", systemImage: "pills.fill").font(.caption).foregroundStyle(Theme.secondary)
                        Text("\(data.supplementsTaken) / \(data.supplementsPlanned)").font(.title3.bold().monospacedDigit())
                        if let next = data.nextSupplement { Text("Далее: \(next)").font(.caption2).foregroundStyle(Theme.secondary) }
                    }
                }
                let nutrition = data.metrics.filter { [.calories, .protein, .fiber].contains($0.kind) }
                if !nutrition.isEmpty {
                    watchCard {
                        Label("Питание", systemImage: "fork.knife").font(.caption).foregroundStyle(Theme.secondary)
                        ForEach(nutrition) { value in
                            HStack {
                                Text(value.kind == .calories ? "Энергия" : value.kind.title)
                                Spacer(minLength: 2)
                                Text("\(Int(value.value.rounded())) \(value.kind.unit)").bold().monospacedDigit()
                            }.font(.caption)
                        }
                    }
                }
                if !data.healthEnabled {
                    Text("Данные здоровья можно подключить в «Ритме» на iPhone.").font(.caption).foregroundStyle(Theme.secondary)
                }
                Text("Синхронизация: \(data.generatedAt.formatted(.dateTime.hour().minute()))")
                    .font(.caption2).foregroundStyle(Theme.secondary)
            } else {
                watchCard {
                    Image(systemName: "iphone.and.arrow.forward").font(.title2).foregroundStyle(Theme.accent)
                    Text("Ваш день на запястье").font(.headline)
                    Text("Откройте «Ритм» на iPhone. Здесь появятся сон, ВСР, движение и питание.").font(.caption).foregroundStyle(Theme.secondary)
                }
                Button("+ 250 мл воды", systemImage: "drop.fill") { health.addWater(250) }
            }
            WatchSyncStatus(health: health)
            Button { health.refresh() } label: {
                Label(health.refreshing ? "Обновляем…" : "Обновить", systemImage: "arrow.clockwise")
            }.disabled(health.refreshing)
        }
        .accessibilityIdentifier("watch.overview")
    }

    private func metric(_ metric: WatchHealthMetric, icon: String, large: Bool = false) -> some View {
        watchCard {
            Label(metric.kind == .hrv ? "ВСР" : metric.kind.title, systemImage: icon).font(.caption2).foregroundStyle(Theme.secondary)
            if metric.kind == .sleep {
                Text("\(Int(metric.value) / 60) ч \(Int(metric.value) % 60) мин")
                    .font(.title2.bold().monospacedDigit()).foregroundStyle(Theme.accent)
            } else {
                Text(Int(metric.value.rounded()), format: .number)
                    .font(large ? .title2.bold().monospacedDigit() : .title3.bold().monospacedDigit())
                    .foregroundStyle(metric.kind == .hrv ? Theme.accent : Theme.primary)
                if metric.kind != .steps { Text(metric.kind.unit).font(.caption2).foregroundStyle(Theme.secondary) }
            }
            if metric.kind == .hrv, let lower = metric.rangeLower, let upper = metric.rangeUpper {
                Text("Обычно \(Int(lower))–\(Int(upper))").font(.caption2).foregroundStyle(Theme.secondary)
            }
            if metric.kind == .pulse || !Calendar.current.isDateInToday(metric.measuredAt) {
                Text(metric.measuredAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption2).foregroundStyle(Theme.secondary)
            }
        }
        .privacySensitive()
        .accessibilityElement(children: .combine)
    }

    private func water(_ data: WatchHealthSnapshot) -> some View {
        watchCard {
            Label("Вода", systemImage: "drop.fill").font(.caption).foregroundStyle(Theme.secondary)
            let today = data.isToday(at: .now)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(today ? "\(Int(data.waterML))" : "—").font(.title2.bold().monospacedDigit())
                Text("/ \(data.waterGoal) мл").font(.caption).foregroundStyle(Theme.secondary)
            }
            if today { ProgressView(value: min(data.waterML, Double(data.waterGoal)), total: Double(data.waterGoal)).tint(Theme.accent) }
            let portions = Array(data.waterPortions.prefix(3))
            pair {
                ForEach(portions, id: \.self) { portion in
                    Button("+\(portion)") { health.addWater(portion) }
                        .font(.caption.weight(.semibold)).frame(minHeight: 44)
                        .accessibilityLabel("Добавить \(portion) миллилитров воды")
                }
            }
        }
    }
}

private struct WatchWellbeing: View {
    let health: WatchHealthStore
    @State private var editor = false
    var body: some View {
        WatchPage {
            Text("Как вы?").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text("Самочувствие").font(.caption).foregroundStyle(Theme.secondary)
            if let checkIn = health.currentCheckIn {
                watchCard {
                    Text(checkIn.date, format: .dateTime.hour().minute()).font(.caption2).foregroundStyle(Theme.secondary)
                    ForEach(WatchCheckInField.allCases) { field in
                        if let value = checkIn.ratings[field.rawValue] {
                            HStack {
                                Text(field.title).font(.caption)
                                Spacer(minLength: 4)
                                Text("\(value)").font(.title3.bold().monospacedDigit()).foregroundStyle(Theme.accent)
                                Text("/ 5").font(.caption2).foregroundStyle(Theme.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            } else {
                watchCard {
                    Image(systemName: "person.crop.circle.badge.checkmark").font(.largeTitle).foregroundStyle(Theme.accent)
                    Text("Отметьте своё состояние").font(.headline)
                    Text("Энергия, стресс и самочувствие попадут в дневник и анализ на iPhone.").font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            Button(health.currentCheckIn == nil ? "Отметить" : "Новая отметка", systemImage: "plus.circle.fill") { editor = true }
                .tint(Theme.accent).accessibilityIdentifier("watch.checkIn")
            Text("Можно заполнить только то, что важно сейчас.").font(.caption2).foregroundStyle(Theme.secondary)
            WatchSyncStatus(health: health)
        }
        .sheet(isPresented: $editor) { WatchCheckInEditor(health: health) }
    }
}

private struct WatchCheckInEditor: View {
    let health: WatchHealthStore
    @Environment(\.dismiss) private var dismiss
    @State private var ratings: [String: Int] = [:]
    var body: some View {
        NavigationStack {
            Form {
                ForEach(WatchCheckInField.allCases) { field in
                    Section {
                        Picker(field.title, selection: Binding(get: { ratings[field.rawValue] ?? 0 }, set: { ratings[field.rawValue] = $0 })) {
                            Text("Не оценивал").tag(0)
                            ForEach(1...5, id: \.self) { value in Text("\(value) / 5").tag(value) }
                        }
                    } footer: { Text(field.endpoints) }
                }
                Button("Сохранить", systemImage: "checkmark") {
                    if health.checkIn(ratings.filter { $0.value > 0 }) { dismiss() }
                }
                .disabled(!ratings.values.contains(where: { $0 > 0 }))
                .accessibilityIdentifier("watch.checkIn.save")
            }
            .navigationTitle("Самочувствие")
        }.tint(Theme.accent)
    }
}

private struct WatchSettings: View {
    let health: WatchHealthStore
    let rest: WatchRestAlert
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Отдых") {
                    Picker("Вибрация", selection: Binding(get: { rest.style }, set: { rest.style = $0 })) {
                        ForEach(WatchRestStyle.allCases) { value in Text(value.title).tag(value) }
                    }
                    Button("Проверить сигнал", systemImage: "waveform") { rest.test() }
                    Text("Два системных сигнала. Сила зависит от настроек тактильных сигналов watchOS.")
                        .font(.caption2).foregroundStyle(Theme.secondary)
                    if let message = rest.permissionMessage { Text(message).font(.caption2) }
                }
                Section("iPhone") {
                    Label(health.link.reachable ? "На связи" : "Нет прямой связи", systemImage: health.link.reachable ? "checkmark.circle" : "iphone.slash")
                    if let date = health.snapshot?.generatedAt { Text(date, format: .dateTime.day().month().hour().minute()) }
                    Text("Ожидают отправки: \(health.pending)")
                    Button("Обновить") { health.refresh() }
                }
                Button("Готово") { dismiss() }
            }
            .navigationTitle("Настройки")
        }.tint(Theme.accent)
    }
}

private struct WatchSyncStatus: View {
    let health: WatchHealthStore
    var body: some View {
        if health.pending > 0 {
            Label("На часах сохранено: \(health.pending). Ждём iPhone.", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption2).foregroundStyle(Theme.warning)
        }
        if let message = health.message { Text(message).font(.caption2).foregroundStyle(Theme.secondary) }
    }
}

private func watchCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6, content: content)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border.opacity(0.65), lineWidth: 1) }
}
