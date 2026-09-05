import CryptoKit
import Foundation
import Security

public enum KokoroAuthenticationError: LocalizedError {
    case alreadyInProgress, couldNotStart, invalidCallback, stateMismatch, accessDenied
    case expired, noPendingLogin, invalidVerifier

    public var errorDescription: String? {
        switch self {
        case .alreadyInProgress:
            return String(localized: "A Kokoro sign-in is already in progress.")
        case .couldNotStart:
            return String(localized: "Could not open the Kokoro sign-in page.")
        case .invalidCallback:
            return String(localized: "Kokoro returned an invalid sign-in callback.")
        case .stateMismatch:
            return String(localized: "Kokoro sign-in could not be verified. Please try again.")
        case .accessDenied:
            return String(localized: "Kokoro sign-in was denied or this account is not authorized.")
        case .expired, .noPendingLogin, .invalidVerifier:
            return String(localized: "Sign in to Kokoro again to continue.")
        }
    }
}

/// Short-lived secrets. Never serialize, log, or include in error payloads.
public struct KokoroPendingLogin {
    public static let lifetime: TimeInterval = 300
    let state: String
    let codeVerifier: String
    let redirectURI: String
    let expiry: Date

    public init(now: Date = Date()) throws {
        state = try Self.randomString()
        codeVerifier = try Self.randomString()
        redirectURI = KokoroAPI.redirectURI
        expiry = now.addingTimeInterval(Self.lifetime)
    }

    public func loginURL() throws -> URL {
        try KokoroAPI.loginURL(state: state, codeChallenge: Self.challenge(for: codeVerifier))
    }

    static func challenge(for verifier: String) throws -> String {
        let bytes = Array(verifier.utf8)
        guard (43 ... 128).contains(bytes.count), bytes.allSatisfy({
            (65 ... 90).contains($0) || (97 ... 122).contains($0) || (48 ... 57).contains($0)
                || [45, 46, 95, 126].contains($0)
        }) else { throw KokoroAuthenticationError.invalidVerifier }
        return base64URL(Data(SHA256.hash(data: Data(bytes))))
    }

    private static func randomString() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw KokoroAPIError.keychain(status: status) }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// Only a validated, consumed callback can create an authorization exchange.
public struct KokoroAuthorization {
    let code: String
    let codeVerifier: String
    let redirectURI: String
    fileprivate init(code: String, login: KokoroPendingLogin) {
        self.code = code
        codeVerifier = login.codeVerifier
        redirectURI = login.redirectURI
    }
}

/// The owning authentication session serializes access on the main actor.
public struct KokoroLoginTransaction {
    private var pending: KokoroPendingLogin?

    public init() {}

    public mutating func begin(now: Date = Date()) throws -> KokoroPendingLogin {
        if let pending, pending.expiry > now { throw KokoroAuthenticationError.alreadyInProgress }
        pending = nil
        let login = try KokoroPendingLogin(now: now)
        pending = login
        return login
    }

    public mutating func cancel() { pending = nil }

    public mutating func consume(_ url: URL, now: Date = Date()) throws -> KokoroAuthorization {
        // Consume before validation: a failed attempt cannot be reused or downgraded.
        let login = pending
        pending = nil
        guard let login else { throw KokoroAuthenticationError.noPendingLogin }
        guard now < login.expiry else { throw KokoroAuthenticationError.expired }
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme == "kokoro", c.host == "oauth", c.percentEncodedHost == "oauth",
              c.percentEncodedPath == "/callback", c.port == nil,
              c.user == nil, c.password == nil, c.fragment == nil,
              // Reject even empty ports and noncanonical authorities.
              url.absoluteString.hasPrefix(login.redirectURI + "?")
        else { throw KokoroAuthenticationError.invalidCallback }

        let items = c.queryItems ?? []
        let securityNames: Set<String> = ["state", "code", "error", "error_description", "error_uri",
                                          "code_verifier", "code_challenge", "code_challenge_method", "redirect_uri"]
        for name in securityNames {
            guard items.filter({ $0.name == name }).count <= 1 else {
                throw KokoroAuthenticationError.invalidCallback
            }
        }
        guard let state = items.first(where: { $0.name == "state" })?.value,
              Self.constantTimeEqual(state, login.state)
        else { throw KokoroAuthenticationError.stateMismatch }

        let codes = items.filter { $0.name == "code" }
        let errors = items.filter { $0.name == "error" }
        guard codes.isEmpty != errors.isEmpty else { throw KokoroAuthenticationError.invalidCallback }
        if let error = errors.first {
            guard let value = error.value, !value.isEmpty else { throw KokoroAuthenticationError.invalidCallback }
            // Never propagate arbitrary server text or URLs into alerts/crash reports.
            if value == "access_denied" { throw KokoroAuthenticationError.accessDenied }
            throw KokoroAuthenticationError.invalidCallback
        }
        guard let code = codes.first?.value, !code.isEmpty else { throw KokoroAuthenticationError.invalidCallback }
        _ = try KokoroPendingLogin.challenge(for: login.codeVerifier)
        return KokoroAuthorization(code: code, login: login)
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        var difference = a.count ^ b.count
        for i in 0 ..< max(a.count, b.count) {
            difference |= Int((i < a.count ? a[i] : 0) ^ (i < b.count ? b[i] : 0))
        }
        return difference == 0
    }
}
