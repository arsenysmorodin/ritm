import SwiftUI

#if !RITM_PREVIEW
@main struct RitmApp: App {
    @State private var store = JournalStore.live()
    @State private var health = HealthConnection()
    @State private var watch = WatchLink()

    var body: some Scene {
        WindowGroup {
            RootView(store: store, health: health, watch: watch)
                .preferredColorScheme(.dark)
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
    let store: JournalStore
    let health: HealthConnection
    var watch: WatchLink? = nil
    @Environment(\.scenePhase) private var scene
    @State private var tab = Tab.today
    @State private var showWorkout = false
    @State private var historyRecord: UUID?
    @State private var today = Date.now

    private enum Tab: Hashable { case today, programs, history, health }

    var body: some View {
        Group {
            if store.isReadable {
                TabView(selection: $tab) {
                    TodayView(
                        store: store, start: start, programs: { tab = .programs },
                        openHistory: { tab = .history }, openRecord: { id in
                            historyRecord = id
                            tab = .history
                        },
                        now: today
                    )
                        .tabItem { Label("Сегодня", systemImage: "house") }.tag(Tab.today)
                    ProgramsView(store: store, start: start)
                        .tabItem { Label("Программы", systemImage: "square.stack") }.tag(Tab.programs)
                    HistoryView(store: store, health: health, selected: $historyRecord)
                        .tabItem { Label("История", systemImage: "clock.arrow.circlepath") }.tag(Tab.history)
                    HealthView(store: store, health: health)
                        .tabItem { Label("Здоровье", systemImage: "heart") }.tag(Tab.health)
                }
            } else {
                Page {
                    HintPanel(icon: "externaldrive.badge.exclamationmark", title: "Журнал недоступен", text: "Исходный файл остался на устройстве. Попробуйте открыть журнал ещё раз.")
                    ActionButton(title: "Открыть журнал", icon: "arrow.clockwise") { store.reload() }
                }
            }
        }
        .foregroundStyle(Ink.primary)
        .tint(Ink.lilac)
        .modifier(WorkoutPresentation(show: $showWorkout) {
            SessionView(store: store, health: health) { record in
                tab = .history
                Task { await health.exportPending(store) }
                if store.journal.healthEnabled {
                    Task {
                        let points = await health.recentPulse(from: record.startedAt, through: record.endedAt)
                        store.mergePulse(points, workoutID: record.id)
                    }
                }
            }.tint(Ink.lilac)
        })
        .onChange(of: scene, initial: true) { _, phase in
            if phase == .active {
                today = .now
                store.publishWidgets()
                if tab == .health { Task { await health.refresh(store) } }
                Task { await health.exportPending(store) }
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                today = .now
                if scene == .active && tab == .health { await health.refresh(store) }
            }
        }
        .onOpenURL { url in
            guard url.scheme == "ritm" else { return }
            if url.host == "history" { tab = .history }
            if url.host == "today" {
                tab = .today
                if store.journal.activeWorkout != nil { showWorkout = true }
            }
        }
        .onChange(of: store.watchSnapshot, initial: true) { _, snapshot in
            watch?.onEvent = { event in store.receiveWatch(event) }
            watch?.publish(snapshot)
        }
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
        .storageAlert(store)
    }

    private func start(_ routine: Routine?) {
        if store.start(routine) { showWorkout = true }
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
