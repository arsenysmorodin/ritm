#if os(iOS)
import ActivityKit
import Observation
import UIKit
import UserNotifications

@MainActor @Observable
final class RestTimerDelivery {
    nonisolated static let notificationPrefix = "ritm.rest."
    private let notifications = UNUserNotificationCenter.current()
    private var current: WorkoutRest?
    private var didReconcile = false
    private var displayedRest: WorkoutRest?
    private var activityTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    var openWorkout = false
    var openHealthRoute: String?

    func sync(_ rest: WorkoutRest?, isForeground: Bool) {
        let previous = current
        let changed = !didReconcile || previous != rest
        guard changed || isForeground else { return }
        didReconcile = true
        current = rest

        if changed, let previous, previous != rest {
            removeNotifications(for: previous)
        }
        activityTask?.cancel()
        activityTask = Task { await reconcileActivity(for: rest, mayStart: isForeground) }
        notificationTask?.cancel()
        notificationTask = Task { await reconcileNotification(for: rest, mayAsk: isForeground) }
    }

    private func reconcileActivity(for rest: WorkoutRest?, mayStart: Bool) async {
        var alreadyActive = false
        for activity in Activity<RestActivityAttributes>.activities {
            guard !Task.isCancelled else { return }
            if let rest, rest.endsAt > .now,
               activity.attributes.workoutID == rest.workoutID && activity.attributes.endsAt == rest.endsAt {
                alreadyActive = true
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        guard !Task.isCancelled, let rest, rest.endsAt > .now else { return }
        if alreadyActive {
            displayedRest = rest
        } else if mayStart, UIApplication.shared.applicationState != .background,
                  displayedRest != rest, ActivityAuthorizationInfo().areActivitiesEnabled {
            let attributes = RestActivityAttributes(workoutID: rest.workoutID, endsAt: rest.endsAt)
            let content = ActivityContent(state: RestActivityAttributes.ContentState(startedAt: .now), staleDate: rest.endsAt)
            do {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
                displayedRest = rest
            } catch {
                // iOS can reject an activity while the app moves into the background.
            }
        }

        try? await Task.sleep(for: .seconds(max(0, rest.endsAt.timeIntervalSinceNow)))
        guard !Task.isCancelled, current == rest else { return }
        for activity in Activity<RestActivityAttributes>.activities
            where activity.attributes.workoutID == rest.workoutID && activity.attributes.endsAt == rest.endsAt {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func reconcileNotification(for rest: WorkoutRest?, mayAsk: Bool) async {
        let pending = await notifications.pendingNotificationRequests()
        guard !Task.isCancelled else { return }
        let identifier = rest.map(notificationID)
        let obsolete = pending.map(\.identifier).filter { $0.hasPrefix(Self.notificationPrefix) && $0 != identifier }
        notifications.removePendingNotificationRequests(withIdentifiers: obsolete)
        guard let rest, let identifier, rest.endsAt > .now,
              !pending.contains(where: { $0.identifier == identifier }) else { return }

        var settings = await notifications.notificationSettings()
        guard !Task.isCancelled else { return }
        if settings.authorizationStatus == .notDetermined, mayAsk,
           UIApplication.shared.applicationState != .background {
            _ = try? await notifications.requestAuthorization(options: [.alert, .sound])
            settings = await notifications.notificationSettings()
        }
        guard !Task.isCancelled, current == rest,
              [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
        let seconds = rest.endsAt.timeIntervalSinceNow
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Отдых завершён"
        content.body = "Можно переходить к следующему подходу."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        try? await notifications.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        if current != rest { removeNotifications(for: rest) }
    }

    private func removeNotifications(for rest: WorkoutRest) {
        let identifier = notificationID(rest)
        notifications.removePendingNotificationRequests(withIdentifiers: [identifier])
        notifications.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private func notificationID(_ rest: WorkoutRest) -> String {
        "\(Self.notificationPrefix)\(rest.workoutID.uuidString).\(rest.endsAt.timeIntervalSinceReferenceDate)"
    }
}

final class RestTimerDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let restTimer = RestTimerDelivery()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.identifier.hasPrefix(RestTimerDelivery.notificationPrefix) || notification.request.identifier.hasPrefix("ritm.health.") ? [.banner, .sound] : []
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        if response.notification.request.identifier.hasPrefix(RestTimerDelivery.notificationPrefix) {
            await MainActor.run { restTimer.openWorkout = true }
        } else if response.notification.request.identifier.hasPrefix("ritm.health."),
                  let route = response.notification.request.content.userInfo["ritmRoute"] as? String {
            await MainActor.run { restTimer.openHealthRoute = route }
        }
    }
}
#endif
