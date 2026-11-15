import Foundation

struct WidgetSnapshot: Codable, Equatable {
    static let workoutKind = "RitmWorkoutWidget"
    static let weekKind = "RitmWeekWidget"

    let activeWorkout: String?
    let completedSets: Int
    let totalSets: Int
    let routines: [Scheduled]
    let completions: [Completion]
    let weeklyGoal: Int

    struct Scheduled: Codable, Equatable {
        let id: UUID
        let title: String
        let weekday: Int?
    }

    struct Completion: Codable, Equatable {
        let routineID: UUID?
        let date: Date
    }

    func suggestion(at date: Date, calendar: Calendar = .current) -> String? {
        let weekday = calendar.component(.weekday, from: date)
        let finishedToday = Set(completions.filter { calendar.isDate($0.date, inSameDayAs: date) }.compactMap(\.routineID))
        let remaining = routines.filter { !finishedToday.contains($0.id) }
        return (remaining.first { $0.weekday == weekday } ?? remaining.first ?? routines.first)?.title
    }

    func week(at date: Date, calendar base: Calendar = .current) -> [Int] {
        var calendar = base
        calendar.firstWeekday = 2
        guard let span = calendar.dateInterval(of: .weekOfYear, for: date) else { return Array(repeating: 0, count: 7) }
        var result = Array(repeating: 0, count: 7)
        for record in completions where record.date >= span.start && record.date < span.end {
            let offset = (calendar.component(.weekday, from: record.date) + 5) % 7
            result[offset] += 1
        }
        return result
    }

    static func load() -> WidgetSnapshot? {
        guard let url = storageURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    static func write(_ snapshot: Self) throws {
        guard let file = storageURL else { throw CocoaError(.fileWriteNoPermission) }
        var folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #if os(iOS)
        var properties = URLResourceValues()
        properties.isExcludedFromBackup = true
        try folder.setResourceValues(properties)
        try JSONEncoder().encode(snapshot).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
        #endif
    }

    private static var storageURL: URL? {
        guard let groupID = Bundle.main.object(forInfoDictionaryKey: "RitmWidgetGroup") as? String, !groupID.isEmpty,
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else { return nil }
        return root.appending(path: "Widget", directoryHint: .isDirectory).appending(path: "snapshot.json")
    }
}
