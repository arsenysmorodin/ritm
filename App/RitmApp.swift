import SwiftUI

#if !RITM_PREVIEW
@main struct RitmApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(RestTimerDelegate.self) private var delegate
    #endif
    @State private var store: JournalStore
    @State private var health: HealthConnection
    @State private var watch: WatchLink
    @AppStorage(RitmAppearance.key) private var appearance = RitmAppearance.system
    @AppStorage(RitmAccent.appKey) private var appAccent = RitmAccent.lime

    init() {
        let journal = HealthOSUITestSupport.journal()
        let link = WatchLink()
        let health = HealthConnection()
        health.startWidgetUpdates(journal)
        link.onEvent = { event in journal.receiveWatch(event) }
        link.publish(journal.watchSnapshot)
        _store = State(initialValue: journal)
        _health = State(initialValue: health)
        _watch = State(initialValue: link)
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store, health: health, watch: watch)
                .modifier(HealthOSUITestDisplay())
                .environment(\.ritmAccent, appAccent.color)
                .preferredColorScheme(appearance.scheme)
                #if os(iOS)
                .environment(delegate.restTimer)
                #endif
                #if os(macOS)
                .frame(minWidth: 360, minHeight: 620)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 402, height: 760)
        #endif
    }
}

#endif

struct RootView: View {
    @Environment(\.ritmAccent) private var accent
    let store: JournalStore
    let health: HealthConnection
    var watch: WatchLink? = nil
    @Environment(\.scenePhase) private var scene
    #if os(iOS)
    @Environment(RestTimerDelivery.self) private var restTimer
    #endif
    @State private var tab = Tab.today
    @State private var showWorkout = false
    @State private var showAppearance = false
    @State private var showBackup = false
    @State private var historyRecord: UUID?
    @State private var historyProgress: TrainingProgressView.Section?
    @State private var healthPath: [RecoverySection] = []
    @State private var trainingPath: [TrainingDestination] = []
    @State private var metricPath: [HealthMeasure] = []
    @State private var today = Date.now
    @State private var daily = HealthOSUITestSupport.healthOS()
    @State private var healthOSBridge = HealthOSBridge()
    @State private var quickEntry: HealthEventKind?
    @State private var showSupplements = false
    @State private var showDayTimeline = false

    private enum Tab: Hashable { case today, health, dynamics, training }
    private enum TrainingDestination: Hashable { case programs, history }

    var body: some View {
        Group {
            if store.isReadable || daily.isReadable {
                TabView(selection: $tab) {
                    DayDashboardView(journal: store, health: health, store: daily, bridge: healthOSBridge,
                        openSettings: { showAppearance = true }, openTraining: { tab = .training; trainingPath = [] },
                        resumeTraining: { start(nil) }, date: today)
                        .tabItem { Label("Сегодня", systemImage: "house") }.tag(Tab.today)
                    HealthView(store: store, health: health, path: $healthPath)
                        .tabItem { Label("Здоровье", systemImage: "heart") }.tag(Tab.health)
                    NavigationStack(path: $metricPath) {
                        HealthInsightsView(store: daily, journal: store)
                            .navigationDestination(for: HealthMeasure.self) { metric in HealthMetricDetail(store: daily, metric: metric) }
                    }
                    .tabItem { Label("Динамика", systemImage: "chart.xyaxis.line") }.tag(Tab.dynamics)
                    trainingArea
                        .tabItem { Label("Тренировки", systemImage: "figure.strengthtraining.traditional") }.tag(Tab.training)
                }
                .storageAlert(store)
            } else {
                journalUnavailable
            }
        }
        .foregroundStyle(Theme.primary)
        .tint(accent)
        .sheet(isPresented: $showAppearance) { AppearanceSettings(store: store) }
        .sheet(item: $quickEntry) { kind in HealthEventEditor(store: daily, kind: kind) }
        .sheet(isPresented: $showSupplements) {
            NavigationStack {
                SupplementsView(store: daily)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { showSupplements = false } } }
            }
        }
        .sheet(isPresented: $showDayTimeline) {
            NavigationStack {
                DayTimelineView(store: daily, journal: store)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { showDayTimeline = false } } }
            }
        }
        .sheet(isPresented: $showBackup) {
            NavigationStack {
                BackupView(store: store)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { showBackup = false } } }
            }
        }
        .modifier(WorkoutPresentation(show: $showWorkout) {
            SessionView(store: store, health: health) { record in
                tab = .today
                trainingPath = []
                Task { await health.exportPending(store) }
                if store.journal.healthEnabled {
                    Task {
                        let points = await health.recentPulse(from: record.startedAt, through: record.endedAt)
                        store.mergePulse(points, workoutID: record.id)
                    }
                }
            }.tint(accent)
        })
        .onChange(of: scene, initial: true) { _, phase in
            #if os(iOS)
            store.onRestChanged = { [weak timer = restTimer] rest in
                timer?.sync(rest, isForeground: UIApplication.shared.applicationState == .active)
            }
            restTimer.sync(store.journal.activeWorkout?.rest, isForeground: phase == .active)
            #endif
            if phase == .active {
                daily.reload()
                daily.onChange = { [weak osStore = daily, weak osBridge = healthOSBridge, weak journal = store] in
                    guard let osStore else { return }
                    Task {
                        if journal?.journal.healthEnabled == true { await osBridge?.syncIntake(osStore) }
                        _ = await HealthOSNotifications.update(osStore)
                    }
                }
                Task {
                    await healthOSBridge.refresh(store, daily: daily)
                    _ = await HealthOSNotifications.update(daily)
                }
                today = .now
                store.publishWidgets()
                Task {
                    health.startWidgetUpdates(store)
                    if tab == .health { await health.refresh(store) } else { await health.refreshWidgetData(store) }
                }
                Task { await health.exportPending(store) }
            }
        }
        #if os(iOS)
        .onChange(of: restTimer.openWorkout, initial: true) { _, open in
            guard open else { return }
            restTimer.openWorkout = false
            tab = .training
            if store.journal.activeWorkout != nil { showWorkout = true }
        }
        .onChange(of: restTimer.openHealthRoute, initial: true) { _, route in
            guard let route else { return }
            restTimer.openHealthRoute = nil; tab = .today
            if route == "water" { quickEntry = .water }
            if route == "supplements" { showSupplements = true }
        }
        #endif
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                today = .now
                if scene == .active {
                    if tab == .health { await health.refresh(store) } else { await health.refreshWidgetData(store) }
                }
            }
        }
        .onOpenURL { url in
            guard url.scheme == "ritm" else { return }
            if ["water", "caffeine", "supplements", "timeline"].contains(url.host ?? "") {
                showAppearance = false; showWorkout = false; tab = .today
                if url.host == "water" { quickEntry = .water }
                if url.host == "caffeine" { quickEntry = .caffeine }
                if url.host == "supplements" { showSupplements = true }
                if url.host == "timeline" { showDayTimeline = true }
            }
            if url.host == "history" {
                showAppearance = false
                showWorkout = false
                historyRecord = nil
                tab = .training; trainingPath = [.history]
                historyProgress = nil
            }
            if url.host == "weight" {
                showAppearance = false; showWorkout = false
                historyRecord = nil; historyProgress = nil
                tab = .dynamics; metricPath = [.weight]
            }
            if url.host == "today" {
                tab = .training; trainingPath = []
                if store.journal.activeWorkout != nil { showWorkout = true }
            }
            if url.host == "dashboard" { tab = .today }
            if let host = url.host, ["health", "recovery", "sleep", "sleep-vitals", "sleep-schedule"].contains(host) {
                showAppearance = false
                showWorkout = false
                historyRecord = nil
                historyProgress = nil
                switch host {
                case "recovery": healthPath = [.overview]
                case "sleep": healthPath = [.sleep]
                case "sleep-vitals": healthPath = [.vitals]
                case "sleep-schedule": healthPath = [.regularity]
                default: healthPath = []
                }
                tab = .health
            }
        }
        .onChange(of: store.watchSnapshot, initial: true) { _, snapshot in
            watch?.publish(snapshot)
        }
        .onChange(of: store.journal.healthEnabled) { old, enabled in
            if old && !enabled { healthOSBridge.disconnect(daily) }
            if enabled { Task { await healthOSBridge.refresh(store, daily: daily, force: true) } }
        }
        .environment(daily)
        .environment(healthOSBridge)
        .task(id: store.journal.healthEnabled ? store.journal.activeWorkout?.id : nil) {
            guard let draft = store.journal.activeWorkout, store.journal.healthEnabled else { return }
            while !Task.isCancelled {
                let now = Date.now
                let start = max(draft.startedAt, now.addingTimeInterval(-90))
                let points = await health.recentPulse(from: start, through: now)
                guard !Task.isCancelled else { return }
                store.mergePulse(points, workoutID: draft.id, now: now)
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func start(_ routine: Routine?) {
        if store.start(routine) { showWorkout = true }
    }

    private var trainingArea: some View {
        NavigationStack(path: $trainingPath) {
            Group {
                if store.isReadable {
                    TrainingHomeView(store: store, start: start,
                        programs: { trainingPath.append(.programs) }, openHistory: { trainingPath.append(.history) },
                        openRecord: { id in historyRecord = id; trainingPath = [.history] },
                        openAppearance: { showAppearance = true }, now: today)
                } else { journalUnavailable }
            }
            .navigationDestination(for: TrainingDestination.self) { destination in
                switch destination {
                case .programs: ProgramsView(store: store, start: start)
                case .history: HistoryView(store: store, health: health, selected: $historyRecord, progress: $historyProgress)
                }
            }
        }
    }

    private var journalUnavailable: some View {
        Page {
            PageHeader(title: "Журнал недоступен", caption: "Локальные данные тренировок") { EmptyView() }
            Panel { StatusMessage(text: store.error ?? "Исходный файл остался на устройстве. Попробуйте открыть журнал ещё раз.") }
            ActionButton(title: "Открыть журнал", icon: "arrow.clockwise") { store.reload() }
            ActionButton(title: "Восстановить из копии", icon: "arrow.down.document", solid: false) { showBackup = true }
        }
    }
}

private struct WorkoutPresentation<Screen: View>: ViewModifier {
    @Binding var show: Bool
    @ViewBuilder let screen: () -> Screen
    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: $show, content: screen)
        #else
        content.sheet(isPresented: $show) { screen().frame(width: 410, height: 680) }
        #endif
    }
}

extension View {
    func storageAlert(_ store: JournalStore) -> some View {
        alert("Локальный журнал", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("ОК") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}
