import Foundation
import GRDB

// MARK: - Data Model

public struct UsageDataPoint: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "usage_points"

    public let timestamp: Date
    public let fiveHourUtilization: Double
    public let sevenDayUtilization: Double
    public let sonnetUtilization: Double?
    public let opusUtilization: Double?
    public let extraUsageUtilization: Double?
    public let extraUsedCents: Double?
    public let extraLimitCents: Double?

    public init(
        timestamp: Date,
        fiveHourUtilization: Double,
        sevenDayUtilization: Double,
        sonnetUtilization: Double? = nil,
        opusUtilization: Double? = nil,
        extraUsageUtilization: Double? = nil,
        extraUsedCents: Double? = nil,
        extraLimitCents: Double? = nil
    ) {
        self.timestamp = timestamp
        self.fiveHourUtilization = fiveHourUtilization
        self.sevenDayUtilization = sevenDayUtilization
        self.sonnetUtilization = sonnetUtilization
        self.opusUtilization = opusUtilization
        self.extraUsageUtilization = extraUsageUtilization
        self.extraUsedCents = extraUsedCents
        self.extraLimitCents = extraLimitCents
    }

    public enum Columns {
        public static let timestamp = Column(CodingKeys.timestamp)
    }
}

// MARK: - Store

public actor UsageHistoryStore {
    private let dbQueue: DatabaseQueue
    public static let retentionInterval: TimeInterval = 30 * 24 * 3600

    public init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbPath = dir.appendingPathComponent("history.db").path

        let queue: DatabaseQueue
        if let fileQueue = try? DatabaseQueue(path: dbPath) {
            queue = fileQueue
        } else {
            queue = try! DatabaseQueue()
        }
        self.dbQueue = queue
        try? Self.makeMigrator().migrate(queue)
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claude-usage")
    }

    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "usage_points", ifNotExists: true) { t in
                t.column("timestamp", .datetime).notNull()
                t.column("fiveHourUtilization", .double).notNull()
                t.column("sevenDayUtilization", .double).notNull()
                t.column("sonnetUtilization", .double)
                t.column("opusUtilization", .double)
                t.column("extraUsageUtilization", .double)
                t.column("extraUsedCents", .double)
                t.column("extraLimitCents", .double)
            }
            try db.create(indexOn: "usage_points", columns: ["timestamp"])
        }
        return migrator
    }

    public func record(_ point: UsageDataPoint) throws {
        try dbQueue.write { db in
            try point.insert(db)
        }
    }

    public func load() throws -> [UsageDataPoint] {
        try dbQueue.read { db in
            try UsageDataPoint
                .order(UsageDataPoint.Columns.timestamp.asc)
                .fetchAll(db)
        }
    }

    public func load(since interval: TimeInterval) throws -> [UsageDataPoint] {
        let cutoff = Date().addingTimeInterval(-interval)
        return try dbQueue.read { db in
            try UsageDataPoint
                .filter(UsageDataPoint.Columns.timestamp >= cutoff)
                .order(UsageDataPoint.Columns.timestamp.asc)
                .fetchAll(db)
        }
    }

    public func prune(olderThan interval: TimeInterval = retentionInterval) throws {
        let cutoff = Date().addingTimeInterval(-interval)
        try dbQueue.write { db in
            _ = try UsageDataPoint
                .filter(UsageDataPoint.Columns.timestamp < cutoff)
                .deleteAll(db)
        }
    }
}
