import HealthKit
import Observation
import SwiftUI
import WatchKit

@MainActor @Observable final class WatchWorkout: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    let link = WatchLink()
    private let health = HKHealthStore()
    private let heartRate = HKQuantityType(.heartRate)
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private(set) var context: Context?
    private(set) var points: [PulsePoint] = []
    private(set) var busy = false
    private(set) var marking = false
    var message: String?

    struct Context: Codable {
        let id: UUID
        let kind: WorkoutKind
        let startedAt: Date
        let linked: Bool
    }

    private let contextKey = "ritm.watch.workout"
    private let outboxKey = "ritm.watch.outbox"

    override init() {
        super.init()
        link.onActivated = { [weak self] in self?.flush() }
        link.onTransferFailed = { [weak self] event in self?.saveToOutbox(event) }
        if link.active { flush() }
    }

    func start(_ kind: WorkoutKind, phone: WatchSnapshot? = nil) async {
        guard !busy, context == nil else { return }
        busy = true
        defer { busy = false }
        message = nil
        guard HKHealthStore.isHealthDataAvailable() else { message = "«Здоровье» недоступно на этих часах."; return }
        do {
            try await health.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [heartRate])
            if phone == nil && health.authorizationStatus(for: HKObjectType.workoutType()) != .sharingAuthorized {
                message = "Разрешите «Ритму» запись тренировок в «Здоровье»."
                return
            }
            let configuration = HKWorkoutConfiguration()
            configuration.locationType = .indoor
            switch kind {
            case .strength: configuration.activityType = .traditionalStrengthTraining
            case .mobility: configuration.activityType = .flexibility
            case .intervals: configuration.activityType = .highIntensityIntervalTraining
            }
            let session = try HKWorkoutSession(healthStore: health, configuration: configuration)
            let now = Date.now
            let info = Context(id: phone?.workoutID ?? UUID(), kind: kind, startedAt: now, linked: phone != nil)
            setup(session, info: info)
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: configuration)
            session.startActivity(with: now)
            try await builder?.beginCollection(at: now)
            if info.linked && link.companion?.workoutID != info.id { finishLinked() }
        } catch {
            session?.end()
            builder?.discardWorkout()
            clear()
            message = "Не удалось начать тренировку. Проверьте разрешения «Здоровья» и завершите другие запущенные занятия."
        }
    }

    private func setup(_ session: HKWorkoutSession, info: Context) {
        self.session = session
        self.builder = session.associatedWorkoutBuilder()
        self.context = info
        self.points = []
        session.delegate = self
        builder?.delegate = self
        UserDefaults.standard.set(try? JSONEncoder().encode(info), forKey: contextKey)
    }

    func recover() async {
        guard session == nil, !busy,
              let data = UserDefaults.standard.data(forKey: contextKey),
              let info = try? JSONDecoder().decode(Context.self, from: data) else { return }
        busy = true
        defer { busy = false }
        do {
            if let recovered = try await health.recoverActiveWorkoutSession() {
                setup(recovered, info: info)
                if let builder { capture(builder) }
            } else { clear() }
        } catch { clear() }
    }

    func mark(_ snapshot: WatchSnapshot) {
        guard let item = snapshot.next, !marking else { return }
        marking = true
        message = nil
        link.send(.mark(workout: snapshot.workoutID, exercise: item.exerciseID, set: item.setID)) { [weak self] confirmed in
            self?.marking = false
            WKInterfaceDevice.current().play(confirmed ? .success : .failure)
            if !confirmed { self?.message = "Подход не отмечен. Проверьте связь с iPhone." }
        }
    }

    func finishLinked() {
        guard let info = context, info.linked else { return }
        enqueue(.pulse(workout: info.id, points: points))
        session?.end()
        builder?.discardWorkout()
        clear()
    }

    func save() async {
        guard !busy, let info = context, !info.linked, let builder else { return }
        busy = true
        defer { busy = false }
        let end = Date.now
        session?.end()
        do {
            try await builder.endCollection(at: end)
            try await builder.addMetadata([HKMetadataKeySyncIdentifier: info.id.uuidString,
                                           HKMetadataKeySyncVersion: 1, HKMetadataKeyIndoorWorkout: true])
            _ = try await builder.finishWorkout()
            enqueue(.finished(WatchActivity(id: info.id, kind: info.kind.rawValue, startedAt: info.startedAt,
                                            endedAt: end, pulse: points)))
            WKInterfaceDevice.current().play(.success)
            message = "Тренировка сохранена."
        } catch {
            builder.discardWorkout()
            message = "Не удалось сохранить тренировку в «Здоровье»."
        }
        clear()
    }

    private func clear() {
        session = nil
        builder = nil
        context = nil
        points = []
        UserDefaults.standard.removeObject(forKey: contextKey)
    }

    private func enqueue(_ event: WatchEvent) {
        saveToOutbox(event)
        flush()
    }

    private var outbox: [WatchEvent] {
        get {
            guard let data = UserDefaults.standard.data(forKey: outboxKey) else { return [] }
            return (try? JSONDecoder().decode([WatchEvent].self, from: data)) ?? []
        }
        set {
            if newValue.isEmpty { UserDefaults.standard.removeObject(forKey: outboxKey) }
            else { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: outboxKey) }
        }
    }

    private func saveToOutbox(_ event: WatchEvent) {
        outbox.append(event)
    }

    private func flush() {
        let events = outbox
        guard link.active, !events.isEmpty else { return }
        outbox = events.filter { !link.queue($0) }
    }

    private func capture(_ builder: HKLiveWorkoutBuilder) {
        guard self.builder === builder, let info = context,
              let statistics = builder.statistics(for: heartRate), let date = statistics.mostRecentQuantityDateInterval()?.end,
              let bpm = statistics.mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute())),
              (20...300).contains(bpm), date != points.last?.date else { return }
        let point = PulsePoint(date: date, bpm: Int(bpm.rounded()))
        points.append(point)
        if info.linked { link.send(.pulse(workout: info.id, points: [point])) }
    }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard collectedTypes.contains(HKQuantityType(.heartRate)) else { return }
        Task { @MainActor in self.capture(workoutBuilder) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            if self.context?.linked == true { self.finishLinked() } else { self.clear() }
            self.message = "Запись пульса остановлена."
        }
    }
}

@MainActor final class WatchApplicationDelegate: NSObject, WKApplicationDelegate {
    let workout = WatchWorkout()

    func handleActiveWorkoutRecovery() {
        Task { await workout.recover() }
    }
}

@main struct RitmWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchApplicationDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup { WatchHome(workout: delegate.workout) }
    }
}

private struct WatchHome: View {
    let workout: WatchWorkout
    @State private var kind: WorkoutKind = .strength
    @State private var confirmSave = false
    @State private var chooseKind = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let snapshot = workout.link.companion, workout.context?.linked != false {
                    phoneWorkout(snapshot)
                } else if let activity = workout.context {
                    heading(activity.kind.title)
                    Text(activity.startedAt, style: .timer).font(.title3.monospacedDigit())
                    pulse
                    Button("Завершить", systemImage: "checkmark") { confirmSave = true }.tint(Theme.accent)
                } else {
                    heading("Тренировка дома")
                    Button { chooseKind = true } label: {
                        HStack {
                            Label(kind.title, systemImage: kind.icon)
                            Spacer(minLength: 2)
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                    }
                    .accessibilityLabel("Тип тренировки")
                    .accessibilityValue(kind.title)
                    Button("Начать", systemImage: "play.fill") { Task { await workout.start(kind) } }.tint(Theme.accent)
                    Text("Чтобы отмечать подходы с часов, начните программу на iPhone.").font(.footnote).foregroundStyle(.secondary)
                }
                if let message = workout.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 5)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.primary)
        .tint(Theme.accent)
        .navigationTitle("Ритм")
        .disabled(workout.busy)
        .overlay { if workout.busy { ProgressView("Загрузка…") } }
        .task { await workout.recover() }
        .onChange(of: workout.link.companion) { _, snapshot in
            if let active = workout.context, active.linked,
               snapshot?.workoutID != active.id || snapshot?.healthEnabled == false { workout.finishLinked() }
        }
        .confirmationDialog("Сохранить тренировку?", isPresented: $confirmSave, titleVisibility: .visible) {
            Button("Сохранить") { Task { await workout.save() } }
        }
        .confirmationDialog("Тип тренировки", isPresented: $chooseKind, titleVisibility: .visible) {
            ForEach(WorkoutKind.allCases) { choice in
                Button(choice.title) { kind = choice }
            }
        }
    }

    @ViewBuilder private func phoneWorkout(_ value: WatchSnapshot) -> some View {
        heading(value.title)
        Text("\(value.completed) / \(value.total) подходов").font(.headline.monospacedDigit())
        if let rest = value.restUntil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if rest > context.date {
                    Label { Text(timerInterval: context.date...rest, countsDown: true) } icon: { Image(systemName: "timer") }
                        .font(.headline.monospacedDigit()).foregroundStyle(Theme.warning)
                }
            }
        }
        if let next = value.next {
            Text(next.label).font(.footnote).foregroundStyle(.secondary)
            Button("Отметить подход", systemImage: "checkmark.circle") { workout.mark(value) }
                .disabled(workout.marking || !workout.link.reachable)
        }
        if !workout.link.reachable { Text("Ожидаем связь с iPhone").font(.footnote).foregroundStyle(.secondary) }
        if workout.context?.linked == true {
            pulse
            Button("Остановить пульс", systemImage: "stop.circle") { workout.finishLinked() }
        } else if value.healthEnabled {
            Button("Измерять пульс", systemImage: "heart.fill") {
                Task { await workout.start(WorkoutKind(rawValue: value.kind) ?? .strength, phone: value) }
            }.tint(Theme.accent)
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.headline).accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var pulse: some View {
        if let data = PulseSummary(workout.points) {
            VStack(alignment: .leading, spacing: 3) {
                Label("\(data.latest) уд/мин", systemImage: "heart.fill").font(.title3.monospacedDigit()).foregroundStyle(Theme.reference)
                Text("Средний \(data.average) · пик \(data.maximum)").font(.footnote).foregroundStyle(.secondary)
            }.privacySensitive()
        } else {
            Label("Ждём первый замер", systemImage: "heart").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
