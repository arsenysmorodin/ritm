import Foundation
import SQLite3

/// One connection per process. SQLite serializes transactions across app and widgets.
final class HealthDatabase: @unchecked Sendable {
    private var connection: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    struct DatabaseError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    init(url: URL) throws {
        var folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var resources = URLResourceValues(); resources.isExcludedFromBackup = true
        try folder.setResourceValues(resources)
        guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let error = failure(); sqlite3_close(connection); connection = nil; throw error
        }
        sqlite3_busy_timeout(connection, 5000)
        do {
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL")
            try execute("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, payload BLOB NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, date REAL NOT NULL, kind TEXT NOT NULL, external TEXT, payload BLOB NOT NULL)")
            try execute("CREATE INDEX IF NOT EXISTS events_date ON events(date)")
            try execute("CREATE UNIQUE INDEX IF NOT EXISTS events_external ON events(external) WHERE external IS NOT NULL")
            try execute("CREATE TABLE IF NOT EXISTS days (id TEXT PRIMARY KEY, date REAL NOT NULL, payload BLOB NOT NULL)")
            if let version: Int = try value("version"), version != 1 { throw DatabaseError(message: "Неподдерживаемая версия базы Health OS.") }
            try set(1, key: "version")
            #if os(iOS)
            for path in [url.path, url.path + "-wal", url.path + "-shm"] where FileManager.default.fileExists(atPath: path) {
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: path)
            }
            #endif
        } catch { sqlite3_close(connection); connection = nil; throw error }
    }

    deinit { sqlite3_close(connection) }

    static func sharedURL() throws -> URL {
        #if os(iOS)
        guard let group = WidgetStorage.groupID,
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw DatabaseError(message: "Общее хранилище недоступно. Откройте «Ритм» и повторите действие.")
        }
        #else
        let root = URL.applicationSupportDirectory.appending(path: "Ritm")
        #endif
        return root.appending(path: "HealthOS/health.sqlite")
    }

    func archive() throws -> HealthOSArchive {
        try synchronized {
            // A read transaction gives export a consistent cross-table snapshot.
            try execute("BEGIN DEFERRED")
            do {
                let archive = HealthOSArchive(settings: try value("settings") ?? HealthOSSettings(),
                    supplements: try value("supplements") ?? [], events: try records("SELECT payload FROM events ORDER BY date DESC"),
                    days: try records("SELECT payload FROM days ORDER BY date"), experiments: try value("experiments") ?? [])
                try execute("COMMIT"); return archive
            } catch { try? execute("ROLLBACK"); throw error }
        }
    }

    func save(_ event: HealthEvent) throws {
        try synchronized { try insert(event) }
    }

    /// The slot check and insert must be atomic when both a widget and app are tapped.
    @discardableResult func take(_ supplement: Supplement, at slot: Date, skipped: Bool = false, now: Date = .now) throws -> Bool {
        try transaction {
            let all: [HealthEvent] = try records("SELECT payload FROM events WHERE kind='supplement'")
            guard !HealthOSLogic.completedSlot(slot, supplement: supplement.id, events: all) else { return false }
            let event = HealthEvent(kind: .supplement, date: now, offsetSeconds: TimeZone.current.secondsFromGMT(for: now), title: supplement.name,
                amount: supplement.servings, linkedID: supplement.id, scheduledAt: slot,
                skipped: skipped, ingredients: supplement.ingredients)
            try insert(event); return true
        }
    }

    func saveConfiguration(_ archive: HealthOSArchive) throws {
        try transaction {
            try set(archive.settings, key: "settings"); try set(archive.supplements, key: "supplements")
            try set(archive.experiments, key: "experiments")
        }
    }

    func importWindow(from start: Date, to end: Date, events: [HealthEvent], days: [DailyHealth]) throws {
        try transaction {
            // Replace only HealthKit-owned events; an empty successful read removes revoked/deleted samples.
            try rangeDelete("events", from: start, to: end, extra: " AND external IS NOT NULL")
            try rangeDelete("days", from: start, to: end)
            for event in events { try insert(event) }
            for day in days { try insert(day) }
        }
    }

    func clearImported() throws {
        try transaction {
            try execute("DELETE FROM events WHERE external IS NOT NULL")
            try execute("DELETE FROM days")
            var settings: HealthOSSettings = try value("settings") ?? HealthOSSettings()
            settings.importedThrough = nil
            settings.writeIntakeToHealth = false
            try set(settings, key: "settings")
        }
    }

    func restore(_ archive: HealthOSArchive) throws {
        try archive.validate()
        try transaction {
            try execute("DELETE FROM events"); try execute("DELETE FROM days")
            var settings = archive.settings
            settings.writeIntakeToHealth = false // Restoring a file never grants write authorization.
            settings.importedThrough = nil
            try set(settings, key: "settings"); try set(archive.supplements, key: "supplements")
            try set(archive.experiments, key: "experiments")
            for var event in archive.events {
                event.needsHealthSync = false // Do not re-export a backup as new intake.
                try insert(event)
            }
            for day in archive.days { try insert(day) }
        }
    }

    private func insert(_ event: HealthEvent) throws {
        let statement = try prepare("INSERT OR REPLACE INTO events(id,date,kind,external,payload) VALUES(?,?,?,?,?)")
        defer { sqlite3_finalize(statement) }
        bind(event.id.uuidString, at: 1, to: statement)
        sqlite3_bind_double(statement, 2, event.date.timeIntervalSince1970)
        bind(event.kind.rawValue, at: 3, to: statement)
        if let external = event.externalID { bind(external, at: 4, to: statement) } else { sqlite3_bind_null(statement, 4) }
        try bind(event, at: 5, to: statement); try step(statement)
    }

    private func insert(_ day: DailyHealth) throws {
        let statement = try prepare("INSERT OR REPLACE INTO days(id,date,payload) VALUES(?,?,?)")
        defer { sqlite3_finalize(statement) }
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: day.timezone) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        bind(formatter.string(from: day.date), at: 1, to: statement)
        sqlite3_bind_double(statement, 2, day.date.timeIntervalSince1970)
        try bind(day, at: 3, to: statement); try step(statement)
    }

    private func rangeDelete(_ table: String, from start: Date, to end: Date, extra: String = "") throws {
        let statement = try prepare("DELETE FROM \(table) WHERE date>=? AND date<?\(extra)")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, end.timeIntervalSince1970); try step(statement)
    }

    private func value<T: Decodable>(_ key: String) throws -> T? {
        let statement = try prepare("SELECT payload FROM metadata WHERE key=?")
        defer { sqlite3_finalize(statement) }; bind(key, at: 1, to: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw failure() }
        return try decode(statement)
    }

    private func set<T: Encodable>(_ value: T, key: String) throws {
        let statement = try prepare("INSERT OR REPLACE INTO metadata(key,payload) VALUES(?,?)")
        defer { sqlite3_finalize(statement) }; bind(key, at: 1, to: statement)
        try bind(value, at: 2, to: statement); try step(statement)
    }

    private func records<T: Decodable>(_ sql: String) throws -> [T] {
        let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
        var values: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return values }
            guard result == SQLITE_ROW else { throw failure() }
            values.append(try decode(statement))
        }
    }

    private func decode<T: Decodable>(_ statement: OpaquePointer) throws -> T {
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else { throw failure() }
        return try JSONDecoder().decode(T.self, from: Data(bytes: bytes, count: count))
    }

    private func bind<T: Encodable>(_ value: T, at index: Int32, to statement: OpaquePointer) throws {
        let data = try JSONEncoder().encode(value)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), transient) }
    }
    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        return statement
    }
    private func step(_ statement: OpaquePointer) throws { guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() } }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func failure() -> DatabaseError {
        DatabaseError(message: connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Не удалось открыть локальную базу Health OS.")
    }
    private func synchronized<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }; return try body()
    }
    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try synchronized {
            try execute("BEGIN IMMEDIATE")
            do { let result = try body(); try execute("COMMIT"); return result }
            catch { try? execute("ROLLBACK"); throw error }
        }
    }
}
