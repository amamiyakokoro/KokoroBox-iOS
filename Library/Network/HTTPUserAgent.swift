import Foundation

public enum HTTPUserAgent {
    public static let maximumCustomLength = 512

    public static func normalizeCustom(_ value: String?) throws -> String? {
        guard let value else {
            return nil
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }
        guard normalized.count <= maximumCustomLength else {
            throw HTTPUserAgentError.tooLong
        }
        guard !normalized.unicodeScalars.contains(where: { scalar in
            scalar.value < 0x20 || scalar.value == 0x7F
        }) else {
            throw HTTPUserAgentError.containsControlCharacter
        }
        return normalized
    }
}

public enum HTTPUserAgentError: LocalizedError, Sendable {
    case tooLong
    case containsControlCharacter

    public var errorDescription: String? {
        switch self {
        case .tooLong:
            return String(localized: "User-Agent must be 512 characters or fewer.")
        case .containsControlCharacter:
            return String(localized: "User-Agent cannot contain control characters or line breaks.")
        }
    }
}
