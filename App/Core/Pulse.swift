import Foundation

struct PulsePoint: Identifiable, Codable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let bpm: Int

    static func cleaned(_ points: [Self], from start: Date, through end: Date) -> [Self] {
        var byTime: [Date: Self] = [:]
        for point in points where point.date >= start && point.date <= end && (20...300).contains(point.bpm) {
            byTime[point.date] = point
        }
        return byTime.values.sorted { $0.date < $1.date }
    }
}

struct PulseSummary {
    let latest: Int
    let average: Int
    let minimum: Int
    let maximum: Int

    init?(_ points: [PulsePoint]) {
        guard let recent = points.last, let minimum = points.map(\.bpm).min(), let maximum = points.map(\.bpm).max() else { return nil }
        self.latest = recent.bpm
        self.minimum = minimum
        self.maximum = maximum
        self.average = Int((Double(points.reduce(0) { $0 + $1.bpm }) / Double(points.count)).rounded())
    }
}
