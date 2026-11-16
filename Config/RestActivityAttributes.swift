import ActivityKit
import Foundation

struct RestActivityAttributes: ActivityAttributes {
    let workoutID: UUID
    let endsAt: Date

    struct ContentState: Codable, Hashable {
        let startedAt: Date
    }
}
