import Foundation
import Observation

struct WatchSnapshot: Codable, Equatable, Sendable {
    let workoutID: UUID
    let title: String
    let kind: String
    let startedAt: Date
    let completed: Int
    let total: Int
    let next: NextSet?
    let restUntil: Date?
    let healthEnabled: Bool
    var lastPulse: PulsePoint?

    struct NextSet: Codable, Equatable, Sendable {
        let exerciseID: UUID
        let setID: UUID
        let label: String
        var isDrop: Bool?
    }
}

struct WatchActivity: Codable, Sendable {
    let id: UUID
    let kind: String
    let startedAt: Date
    let endedAt: Date
    let pulse: [PulsePoint]
}

enum WatchEvent: Codable, Sendable {
    case mark(workout: UUID, exercise: UUID, set: UUID)
    case pulse(workout: UUID, points: [PulsePoint])
    case finished(WatchActivity)
    case health(WatchHealthAction)
    case requestHealth
    case removeSet(workout: UUID, exercise: UUID, set: UUID)
}

#if os(iOS) || os(watchOS)
import WatchConnectivity

@MainActor @Observable final class WatchLink: NSObject, WCSessionDelegate {
    private(set) var reachable = false
    private(set) var active = false
    private(set) var companion: WatchSnapshot?
    private(set) var companionHealth: WatchHealthSnapshot?
    private var local: WatchSnapshot?
    private var localHealth: WatchHealthSnapshot?
    var onEvent: ((WatchEvent) -> Bool)? {
        didSet {
            guard let onEvent else { return }
            for event in pendingEvents { self.receipt(for: event, accepted: onEvent(event)) }
            pendingEvents = []
        }
    }
    var onActivated: (() -> Void)?
    var onTransferFailed: ((WatchEvent) -> Void)?
    var onHealthSnapshot: ((WatchHealthSnapshot?) -> Void)?
    var onHealthReceipt: ((WatchHealthReceipt) -> Void)?
    var onHealthActivated: (() -> Void)?
    var onHealthTransferFailed: ((WatchHealthAction) -> Void)?
    var onWorkoutSnapshot: ((WatchSnapshot?) -> Void)?
    private var pendingEvents: [WatchEvent] = []

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func publish(_ snapshot: WatchSnapshot?) {
        guard local != snapshot else { return }
        local = snapshot
        sendContext()
    }

    func publishHealth(_ snapshot: WatchHealthSnapshot?) {
        guard localHealth != snapshot else { return }
        localHealth = snapshot
        sendContext()
    }

    private func sendContext() {
        #if os(iOS)
        guard WCSession.default.activationState == .activated, WCSession.default.isPaired,
              let data = try? JSONEncoder().encode(local),
              let state = try? JSONEncoder().encode(WatchAppContext(workout: local, health: localHealth)) else { return }
        try? WCSession.default.updateApplicationContext(["ritm-snapshot": data, "ritm-state-v2": state])
        #endif
    }

    func send(_ event: WatchEvent, reply: ((Bool) -> Void)? = nil) {
        guard WCSession.default.activationState == .activated, reachable,
              let data = try? JSONEncoder().encode(event) else { reply?(false); return }
        let message = ["ritm-event": data]
        if let reply {
            WCSession.default.sendMessage(message, replyHandler: { result in
                let success = result["ok"] as? Bool ?? false
                Task { @MainActor in self.decodeContext(result); reply(success) }
            }, errorHandler: { _ in Task { @MainActor in reply(false) } })
        } else {
            WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
        }
    }

    #if os(watchOS)
    @discardableResult func queue(_ event: WatchEvent) -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        guard WCSession.default.activationState == .activated, WCSession.default.isCompanionAppInstalled,
              let data = try? JSONEncoder().encode(event) else { return false }
        WCSession.default.transferUserInfo(["ritm-event": data])
        return true
        #endif
    }

    var queuedHealthIDs: Set<UUID> {
        Set(WCSession.default.outstandingUserInfoTransfers.compactMap { transfer in
            guard case let .health(action) = Self.event(from: transfer.userInfo) else { return nil }
            return action.id
        })
    }

    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        guard session.isCompanionAppInstalled else { return }
        Task { @MainActor in self.onActivated?(); self.onHealthActivated?() }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        guard error != nil, let event = Self.event(from: userInfoTransfer.userInfo) else { return }
        Task { @MainActor in
            if case let .health(action) = event { self.onHealthTransferFailed?(action) }
            else { self.onTransferFailed?(event) }
        }
    }
    #endif

    private func decodeContext(_ context: [String: Any]) {
        if let data = context["ritm-state-v2"] as? Data,
           let decoded = try? JSONDecoder().decode(WatchAppContext.self, from: data), decoded.version == 2 {
            companion = decoded.workout
            companionHealth = decoded.health
            onHealthSnapshot?(decoded.health)
            onWorkoutSnapshot?(decoded.workout)
        } else if let data = context["ritm-snapshot"] as? Data {
            // A valid JSON null ends the phone workout as well.
            do {
                companion = try JSONDecoder().decode(WatchSnapshot?.self, from: data)
                onWorkoutSnapshot?(companion)
            } catch { }
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let reachable = session.isReachable
        Task { @MainActor in
            self.active = activationState == .activated
            self.reachable = reachable
            self.decodeContext(context)
            self.sendContext()
            if self.active { self.onActivated?(); self.onHealthActivated?() }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.reachable = reachable
            if reachable { self.onActivated?(); self.onHealthActivated?() }
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            self.active = false
            self.reachable = false
        }
    }
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.sendContext() }
    }
    #endif

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in self.decodeContext(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) { receive(userInfo) }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receive(message) }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let event = Self.event(from: message) else { replyHandler(["ok": false]); return }
        Task { @MainActor in
            let accepted = self.onEvent?(event) ?? false
            var result: [String: Any] = ["ok": accepted]
            #if os(iOS)
            result["ritm-state-v2"] = try? JSONEncoder().encode(WatchAppContext(workout: self.local, health: self.localHealth))
            #endif
            replyHandler(result)
        }
    }

    nonisolated private func receive(_ message: [String: Any]) {
        if let data = message["ritm-health-receipt"] as? Data,
           let receipt = try? JSONDecoder().decode(WatchHealthReceipt.self, from: data) {
            Task { @MainActor in self.onHealthReceipt?(receipt) }
            return
        }
        guard let event = Self.event(from: message) else { return }
        Task { @MainActor in
            if let onEvent = self.onEvent {
                let accepted = onEvent(event)
                self.receipt(for: event, accepted: accepted)
            }
            else { self.pendingEvents.append(event) }
        }
    }

    private func receipt(for event: WatchEvent, accepted: Bool) {
        #if os(iOS)
        guard case let .health(action) = event,
              WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(WatchHealthReceipt(id: action.id, accepted: accepted)) else { return }
        WCSession.default.transferUserInfo(["ritm-health-receipt": data])
        #endif
    }

    nonisolated private static func event(from message: [String: Any]) -> WatchEvent? {
        guard let data = message["ritm-event"] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchEvent.self, from: data)
    }
}
#else
@MainActor final class WatchLink {
    var onEvent: ((WatchEvent) -> Bool)?
    func publish(_ snapshot: WatchSnapshot?) {}
    func publishHealth(_ snapshot: WatchHealthSnapshot?) {}
}
#endif
