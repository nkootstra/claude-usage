import Testing
import Foundation
@testable import ClaudeUsageCore

@Suite("UsageResponse parsing")
struct UsageResponseTests {

    // Real API response fixture from https://api.anthropic.com/api/oauth/usage
    let fullFixture = """
    {
        "five_hour": {
            "utilization": 2.0,
            "resets_at": "2026-03-22T07:59:59.916874+00:00"
        },
        "seven_day": {
            "utilization": 17.0,
            "resets_at": "2026-03-27T12:59:59.916893+00:00"
        },
        "seven_day_oauth_apps": null,
        "seven_day_opus": null,
        "seven_day_sonnet": {
            "utilization": 0.0,
            "resets_at": "2026-03-27T09:00:00.916902+00:00"
        },
        "seven_day_cowork": null,
        "iguana_necktie": null,
        "extra_usage": {
            "is_enabled": false,
            "monthly_limit": null,
            "used_credits": null,
            "utilization": null
        }
    }
    """.data(using: .utf8)!

    @Test("Parses full API response with all buckets")
    func parseFullResponse() throws {
        let response = try JSONDecoder().decode(UsageResponse.self, from: fullFixture)

        #expect(response.fiveHour?.utilization == 2.0)
        #expect(response.sevenDay?.utilization == 17.0)
        #expect(response.sevenDaySonnet?.utilization == 0.0)
        #expect(response.sevenDayOpus == nil)
    }

    @Test("Parses reset timestamps into Dates")
    func parseResetDates() throws {
        let response = try JSONDecoder().decode(UsageResponse.self, from: fullFixture)

        let resetDate = try #require(response.fiveHour?.resetsAtDate)
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: resetDate)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 22)
        #expect(components.hour == 7)
    }

    @Test("Extra usage parses disabled state with null fields")
    func parseExtraUsageDisabled() throws {
        let response = try JSONDecoder().decode(UsageResponse.self, from: fullFixture)

        let extra = try #require(response.extraUsage)
        #expect(extra.isEnabled == false)
        #expect(extra.usedCreditsAmount == nil)
        #expect(extra.monthlyLimitAmount == nil)
    }

    @Test("Extra usage converts cents to dollars when enabled")
    func parseExtraUsageEnabled() throws {
        let json = """
        {
            "five_hour": null,
            "seven_day": null,
            "extra_usage": {
                "is_enabled": true,
                "used_credits": 1550,
                "monthly_limit": 10000,
                "utilization": 15.5
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)
        let extra = try #require(response.extraUsage)

        #expect(extra.isEnabled == true)
        #expect(extra.usedCreditsAmount == 15.50)
        #expect(extra.monthlyLimitAmount == 100.00)
        #expect(extra.utilization == 15.5)
    }

    @Test("Ignores unknown fields in response (forward compatibility)")
    func ignoresUnknownFields() throws {
        let response = try JSONDecoder().decode(UsageResponse.self, from: fullFixture)
        #expect(response.fiveHour?.utilization == 2.0)
    }

    @Test("Handles response where all buckets are null")
    func allBucketsNull() throws {
        let json = """
        {
            "five_hour": null,
            "seven_day": null,
            "seven_day_sonnet": null,
            "seven_day_opus": null,
            "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(response.fiveHour == nil)
        #expect(response.sevenDay == nil)
        #expect(response.sevenDaySonnet == nil)
        #expect(response.sevenDayOpus == nil)
    }

    // MARK: - Edge cases: utilization boundary values

    @Test("Utilization at exactly 0% and 100%")
    func utilizationBoundaries() throws {
        let json = """
        {
            "five_hour": { "utilization": 0.0, "resets_at": null },
            "seven_day": { "utilization": 100.0, "resets_at": null },
            "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(response.fiveHour?.utilization == 0.0)
        #expect(response.sevenDay?.utilization == 100.0)
    }

    @Test("Utilization over 100% (overage)")
    func utilizationOverage() throws {
        let json = """
        {
            "five_hour": { "utilization": 142.5, "resets_at": null },
            "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(response.fiveHour?.utilization == 142.5)
    }

    // MARK: - Edge cases: reset date parsing

    @Test("Malformed resets_at returns nil date")
    func malformedResetsAt() throws {
        let json = """
        {
            "five_hour": { "utilization": 10.0, "resets_at": "not-a-date" },
            "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(response.fiveHour?.resetsAtDate == nil)
    }

    @Test("Null resets_at returns nil date")
    func nullResetsAt() throws {
        let json = """
        {
            "five_hour": { "utilization": 50.0, "resets_at": null },
            "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(response.fiveHour?.resetsAtDate == nil)
        #expect(response.fiveHour?.utilization == 50.0)
    }

    @Test("ISO8601 date without fractional seconds")
    func isoDateWithoutFractional() throws {
        let json = """
        {
            "five_hour": { "utilization": 5.0, "resets_at": "2026-03-22T12:00:00+00:00" },
            "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(response.fiveHour?.resetsAtDate != nil)
    }

    // MARK: - Edge cases: extra usage

    @Test("Extra usage with zero credits used")
    func extraUsageZeroCredits() throws {
        let json = """
        {
            "extra_usage": {
                "is_enabled": true,
                "used_credits": 0,
                "monthly_limit": 10000,
                "utilization": 0.0
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)
        let extra = try #require(response.extraUsage)
        #expect(extra.usedCreditsAmount == 0.0)
        #expect(extra.monthlyLimitAmount == 100.0)
    }

    @Test("Extra usage enabled but no utilization data")
    func extraUsageEnabledNoUtilization() throws {
        let json = """
        {
            "extra_usage": {
                "is_enabled": true,
                "used_credits": null,
                "monthly_limit": null,
                "utilization": null
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)
        let extra = try #require(response.extraUsage)
        #expect(extra.isEnabled == true)
        #expect(extra.utilization == nil)
        #expect(extra.usedCreditsAmount == nil)
    }
}
