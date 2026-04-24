import Foundation

/// Persistent best-effort snapshot of the last successful usage fetch, used
/// to hydrate the UI on launch and to defer the first automatic poll when
/// the cached response is still fresh. Corrupt or missing files fall back
/// to the immediate-fetch behavior.
public struct CachedUsageResponse: Codable, Sendable {
    public let fetchedAt: Date
    public let response: UsageResponse

    public init(fetchedAt: Date, response: UsageResponse) {
        self.fetchedAt = fetchedAt
        self.response = response
    }
}

public final class UsageResponseCache: Sendable {
    private let fileURL: URL

    public init(fileURL: URL = UsageResponseCache.defaultURL()) {
        self.fileURL = fileURL
    }

    public static func defaultURL() -> URL {
        let base: URL
        do {
            base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            base = FileManager.default.temporaryDirectory
        }
        let dir = base.appendingPathComponent("cc-stats", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("last-usage.json")
    }

    public func load() -> CachedUsageResponse? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedUsageResponse.self, from: data)
    }

    public func save(_ cached: CachedUsageResponse) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(cached) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
