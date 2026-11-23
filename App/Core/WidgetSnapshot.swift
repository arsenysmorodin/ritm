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
        WidgetStorage.load(Self.self, file: "snapshot.json")
    }

    static func write(_ snapshot: Self) throws {
        try WidgetStorage.write(snapshot, file: "snapshot.json")
    }
}

enum WidgetStorage {
    static var groupID: String? {
        Bundle.main.object(forInfoDictionaryKey: "RitmWidgetGroup") as? String
    }

    static var preferences: UserDefaults {
        groupID.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    static func load<T: Decodable>(_ type: T.Type, file: String) -> T? {
        guard let url = url(for: file), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func write(_ value: some Encodable, file name: String) throws {
        guard let file = url(for: name) else { throw CocoaError(.fileWriteNoPermission) }
        var folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #if os(iOS)
        var properties = URLResourceValues()
        properties.isExcludedFromBackup = true
        try folder.setResourceValues(properties)
        try JSONEncoder().encode(value).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try JSONEncoder().encode(value).write(to: file, options: .atomic)
        #endif
    }

    static func remove(file: String) throws {
        guard let url = url(for: file) else { return }
        do { try FileManager.default.removeItem(at: url) }
        catch let error as CocoaError where error.code == .fileNoSuchFile {}
    }

    private static func url(for name: String) -> URL? {
        guard let groupID, !groupID.isEmpty,
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else { return nil }
        return root.appending(path: "Widget", directoryHint: .isDirectory).appending(path: name)
    }
}
