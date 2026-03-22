import Testing
import Foundation
@testable import ClaudeUsageCore

@Suite("CSVExporter")
struct CSVExporterTests {

    @Test("Exports header and rows")
    func headerAndRows() {
        let points = [
            UsageDataPoint(
                timestamp: ISO8601DateFormatter().date(from: "2026-03-22T10:00:00Z")!,
                fiveHourUtilization: 42.0,
                sevenDayUtilization: 17.0
            ),
            UsageDataPoint(
                timestamp: ISO8601DateFormatter().date(from: "2026-03-22T10:05:00Z")!,
                fiveHourUtilization: 43.0,
                sevenDayUtilization: 17.5
            ),
        ]

        let csv = CSVExporter.export(points)
        let lines = csv.split(separator: "\n")

        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("date,five_hour_pct,seven_day_pct"))
        #expect(lines[1].contains("2026-03-22T10:00:00"))
        #expect(lines[1].contains("42.0"))
        #expect(lines[1].contains("17.0"))
    }

    @Test("Empty points exports header only")
    func emptyExportsHeader() {
        let csv = CSVExporter.export([])
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 1)
        #expect(lines[0].hasPrefix("date,five_hour_pct,seven_day_pct"))
    }

    @Test("Dates are ISO8601 UTC")
    func datesISO8601() {
        let points = [
            UsageDataPoint(
                timestamp: ISO8601DateFormatter().date(from: "2026-03-22T10:00:00Z")!,
                fiveHourUtilization: 5.0,
                sevenDayUtilization: 3.0
            ),
        ]

        let csv = CSVExporter.export(points)
        #expect(csv.contains("2026-03-22T10:00:00Z"))
    }
}
