import Foundation

public enum UsageError: Sendable, Equatable {
    case noCredential
    case unauthorized
    case rateLimited(retryIn: TimeInterval)
    case networkError(String)
    case unknown(String)

    public var isAuthError: Bool {
        switch self {
        case .noCredential, .unauthorized: return true
        default: return false
        }
    }

    public var displayMessage: String {
        switch self {
        case .noCredential:
            return "No credential"
        case .unauthorized:
            return "Unauthorized. Token may be revoked."
        case .rateLimited(let retryIn):
            if retryIn >= 60 {
                return "Rate limited. Retrying in \(Int(retryIn / 60)) min."
            }
            return "Rate limited. Retrying in \(Int(retryIn))s."
        case .networkError(let message):
            return message
        case .unknown(let message):
            return message
        }
    }

    public var debugDescription: String {
        displayMessage
    }
}
