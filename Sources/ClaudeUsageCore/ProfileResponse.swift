import Foundation

public struct ProfileResponse: Codable, Sendable {
    public let account: Account
    public let organization: Organization?

    public struct Account: Codable, Sendable {
        public let uuid: String?
        public let emailAddress: String?
        public let fullName: String?
        public let displayName: String?
        public let memberships: [Membership]?

        enum CodingKeys: String, CodingKey {
            case uuid
            case emailAddress = "email_address"
            case fullName = "full_name"
            case displayName = "display_name"
            case memberships
        }
    }

    public struct Membership: Codable, Sendable {
        public let role: String?
        public let seatTier: String?
        public let organization: Organization?

        enum CodingKeys: String, CodingKey {
            case role
            case seatTier = "seat_tier"
            case organization
        }
    }

    public struct Organization: Codable, Sendable {
        public let uuid: String?
        public let name: String?
        public let capabilities: [String]?
        public let billingType: String?
        public let rateLimitTier: String?

        enum CodingKeys: String, CodingKey {
            case uuid
            case name
            case capabilities
            case billingType = "billing_type"
            case rateLimitTier = "rate_limit_tier"
        }
    }

    /// First membership organization, which is what the Claude app uses for plan display.
    public var primaryOrganization: Organization? {
        organization ?? account.memberships?.first?.organization
    }

    /// Best identifier to show the signed-in user.
    public var displayIdentifier: String? {
        account.displayName ?? account.fullName ?? account.emailAddress
    }
}

/// Derived plan label shown in the menu bar popover and settings.
public enum PlanTier: Sendable, Equatable {
    case enterprise
    case max20x
    case max5x
    case pro
    case free
    case unknown

    public var label: String {
        switch self {
        case .enterprise: return "Enterprise"
        case .max20x: return "Max 20×"
        case .max5x: return "Max 5×"
        case .pro: return "Pro"
        case .free: return "Free"
        case .unknown: return "Claude"
        }
    }

    public static func derive(profile: ProfileResponse?, isEnterprise: Bool) -> PlanTier {
        if isEnterprise { return .enterprise }
        guard let org = profile?.primaryOrganization else { return .unknown }
        let tier = (org.rateLimitTier ?? "").lowercased()
        let caps = org.capabilities ?? []

        if tier.contains("20x") || caps.contains(where: { $0.contains("max_20x") }) {
            return .max20x
        }
        if tier.contains("5x") || caps.contains(where: { $0.contains("max_5x") }) {
            return .max5x
        }
        if caps.contains(where: { $0.contains("claude_max") }) {
            return .max5x
        }
        if caps.contains(where: { $0.contains("claude_pro") }) {
            return .pro
        }
        if org.billingType?.lowercased() == "free" {
            return .free
        }
        return .unknown
    }
}
