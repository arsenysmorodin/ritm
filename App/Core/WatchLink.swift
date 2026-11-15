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

    struct NextSet: Codable, Equatable, Sendable {
        let exerciseID: UUID
        let setID: UUID
        let label: String
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
}

#if os(iOS) || os(watchOS)
import WatchConnectivity

@MainActor @Observable final class WatchLink: NSObject, WCSessionDelegate {
    private(set) var reachable = false
    private(set) var active = false
    private(set) var companion: WatchSnapshot?
    private var local: WatchSnapshot?
    var onEvent: ((WatchEvent) -> Bool)? {
        didSet {
            guard let onEvent else { return }
            for event in pendingEvents { _ = onEvent(event) }
            pendingEvents = []
        }
    }
    var onActivated: (() -> Void)?
    private var pendingEvents: [WatchEvent] = []

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func publish(_ snapshot: WatchSnapshot?) {
        guard local != snapshot || (active && WCSession.default.applicationContext["ritm-snapshot"] == nil) else { return }
        local = snapshot
        sendContext()
    }

    private func sendContext() {
        #if os(iOS)
        guard active, WCSession.default.isPaired, let data = try? JSONEncoder().encode(local) else { return }
        try? WCSession.default.updateApplicationContext(["ritm-snapshot": data])
        #endif
    }

    func send(_ event: WatchEvent, queued: Bool = false, reply: ((Bool) -> Void)? = nil) {
        guard active, let data = try? JSONEncoder().encode(event) else { reply?(false); return }
        let message = ["ritm-event": data]
        if queued {
            WCSession.default.transferUserInfo(message)
        } else if reachable {
            if let reply {
                WCSession.default.sendMessage(message, replyHandler: { result in
                    let success = result["ok"] as? Bool ?? false
                    Task { @MainActor in reply(success) }
                }, errorHandler: { _ in Task { @MainActor in reply(false) } })
            } else {
                WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
            }
        } else {
            reply?(false)
        }
    }

    private func decodeSnapshot(_ data: Data?) {
        if let data, let decoded = try? JSONDecoder().decode(Optional<WatchSnapshot>.self, from: data) {
            companion = decoded
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext["ritm-snapshot"] as? Data
        let reachable = session.isReachable
        Task { @MainActor in
            self.active = activationState == .activated
            self.reachable = reachable
            self.decodeSnapshot(data)
            self.sendContext()
            if self.active { self.onActivated?() }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.reachable = reachable }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.sendContext() }
    }
    #endif

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        let data = context["ritm-snapshot"] as? Data
        Task { @MainActor in self.decodeSnapshot(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) { receive(userInfo) }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receive(message) }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let event = Self.event(from: message) else { replyHandler(["ok": false]); return }
        Task { @MainActor in replyHandler(["ok": self.onEvent?(event) ?? false]) }
    }

    nonisolated private func receive(_ message: [String: Any]) {
        guard let event = Self.event(from: message) else { return }
        Task { @MainActor in
            if let onEvent = self.onEvent { _ = onEvent(event) }
            else { self.pendingEvents.append(event) }
        }
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
}
#endif
