import Observation
import UserNotifications
import WatchKit

enum WatchRestStyle: String, CaseIterable, Identifiable {
    case noticeable, standard, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .noticeable: "Заметный · два сигнала"
        case .standard: "Обычный · один сигнал"
        case .off: "Без сигнала"
        }
    }
}

@MainActor @Observable final class WatchRestAlert {
    static let styleKey = "ritm.watch.rest.signal"
    private let notificationID = "ritm.watch.rest.end"
    private let playedKey = "ritm.watch.rest.played"
    private var signal: WatchRestSignal?
    private var task: Task<Void, Never>?
    private var deliveryTask: Task<Void, Never>?
    private var scheduledID: String?
    private var generation = UUID()
    private var isForeground = true
    private var hasSession = false
    private(set) var permissionMessage: String?
    var style = WatchRestStyle(rawValue: UserDefaults.standard.string(forKey: WatchRestAlert.styleKey) ?? "") ?? .noticeable {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: Self.styleKey); reschedule() }
    }

    init() {
        deliveryTask = Task {
            let center = UNUserNotificationCenter.current()
            let previous = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: previous.filter { $0.identifier.hasPrefix("ritm.watch.rest.end") }.map(\.identifier))
        }
    }

    func update(_ snapshot: WatchSnapshot?, hasWorkoutSession: Bool, foreground: Bool? = nil) {
        let next = snapshot.flatMap { snapshot in
            snapshot.restUntil.map { WatchRestSignal(workoutID: snapshot.workoutID, endsAt: $0) }
        }
        let active = foreground ?? isForeground
        guard next != signal || hasWorkoutSession != hasSession || active != isForeground else { return }
        isForeground = active
        hasSession = hasWorkoutSession
        signal = next
        reschedule()
    }

    func requestPermission() async {
        do {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            let granted = settings.authorizationStatus == .notDetermined
                ? try await center.requestAuthorization(options: [.alert, .sound])
                : settings.authorizationStatus == .authorized
            permissionMessage = granted ? nil : "Для сигнала без активной записи пульса разрешите уведомления «Ритма» в настройках часов."
        } catch { permissionMessage = "Не удалось включить уведомления. Сигнал в открытом приложении доступен." }
        reschedule()
    }

    func test() {
        play()
        Task { await requestPermission() }
    }

    /// In the foreground the app supplies its own haptic and suppresses a duplicate system sound.
    func present(_ notification: UNNotification) {
        guard notification.request.identifier.hasPrefix(notificationID),
              let key = notification.request.content.userInfo["signal"] as? String else { return }
        fire(key)
    }

    private func reschedule() {
        task?.cancel()
        generation = UUID()
        let currentGeneration = generation
        let center = UNUserNotificationCenter.current()
        if let scheduledID { center.removePendingNotificationRequests(withIdentifiers: [scheduledID]) }
        scheduledID = nil
        guard style != .off, let signal, signal.endsAt > .now,
              !(UserDefaults.standard.stringArray(forKey: playedKey) ?? []).contains(signal.key) else { return }
        // An active HealthKit session permits background execution. Otherwise use a local notification.
        if isForeground || hasSession {
            task = Task { [weak self] in
                let delay = max(0, signal.endsAt.timeIntervalSinceNow)
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self, !Task.isCancelled, generation == currentGeneration,
                      Date.now.timeIntervalSince(signal.endsAt) < 5 else { return }
                if let scheduledID { center.removePendingNotificationRequests(withIdentifiers: [scheduledID]) }
                fire(signal.key)
            }
        }
        if !hasSession {
            let requestID = notificationID + "." + currentGeneration.uuidString
            scheduledID = requestID
            let previous = deliveryTask
            deliveryTask = Task { [weak self] in
                await previous?.value
                let settings = await center.notificationSettings()
                guard let self, generation == currentGeneration, signal.endsAt > .now,
                      settings.authorizationStatus == .authorized else { return }
                let content = UNMutableNotificationContent()
                content.title = "Отдых завершён"
                content.body = "Можно переходить к следующему подходу."
                content.sound = .default
                content.userInfo = ["signal": signal.key]
                let request = UNNotificationRequest(identifier: requestID, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, signal.endsAt.timeIntervalSinceNow), repeats: false))
                try? await center.add(request)
                if generation != currentGeneration { center.removePendingNotificationRequests(withIdentifiers: [requestID]) }
            }
        }
    }

    private func fire(_ key: String) {
        var played = UserDefaults.standard.stringArray(forKey: playedKey) ?? []
        guard !played.contains(key), style != .off else { return }
        played.append(key)
        UserDefaults.standard.set(Array(played.suffix(64)), forKey: playedKey)
        play()
    }

    private func play() {
        guard style != .off else { return }
        WKInterfaceDevice.current().play(.notification)
        if style == .noticeable {
            Task {
                try? await Task.sleep(for: .milliseconds(1500))
                guard style == .noticeable else { return }
                WKInterfaceDevice.current().play(.notification)
            }
        }
    }
}
