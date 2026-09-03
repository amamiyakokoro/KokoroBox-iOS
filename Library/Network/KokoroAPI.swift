import Foundation
import Security

private final class KokoroURLSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = KokoroURLSessionDelegate()

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public enum KokoroAPIError: LocalizedError, Sendable {
    case invalidResponse
    case invalidConfigurationURL
    case invalidContentType
    case unsupportedConfiguration
    case noSession
    case http(status: Int, detail: String?)
    case keychain(status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return String(localized: "Kokoro returned an invalid response.")
        case .invalidConfigurationURL:
            return String(localized: "Kokoro returned an invalid configuration URL.")
        case .invalidContentType:
            return String(localized: "Kokoro returned a configuration in an unexpected format.")
        case .unsupportedConfiguration:
            return String(localized: "Kokoro does not currently offer a compatible sing-box subscription.")
        case .noSession:
            return String(localized: "Sign in to Kokoro again to continue.")
        case let .http(status, detail):
            if let detail, !detail.isEmpty {
                return String(localized: "Kokoro request failed (HTTP \(status)): \(detail)")
            }
            return String(localized: "Kokoro request failed (HTTP \(status)).")
        case let .keychain(status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? String(localized: "Unknown Keychain error")
            return String(localized: "Could not access the Kokoro session in Keychain: \(message)")
        }
    }
}

public struct KokoroPlan: Codable, Hashable, Sendable {
    public let name: String
    public let description: String?
    public let supportedIsps: [String]
}

public struct KokoroUser: Codable, Sendable {
    public let osuId: String
    public let username: String?
    public let avatarUrl: String?
    public let plans: [String]
    public let plansDetails: [KokoroPlan]
    public let trafficUsage: Int64
    public let bandwidthLimit: Int64
    public let subscriptionExpiresAt: String?
}

public struct KokoroFormatOption: Codable, Hashable, Sendable {
    public let value: String
    public let contentType: String
    public let filename: String
    public let targetVersion: String?
    public let testing: Bool
}

public struct KokoroProtocolOption: Codable, Hashable, Sendable {
    public let value: String
    public let label: String
    public let supportsDirect: Bool
}

public struct KokoroISPOption: Codable, Hashable, Sendable {
    public let value: String
    public let label: String
}

public struct KokoroProfileUpdateRange: Codable, Sendable {
    public let minHours: Int
    public let maxHours: Int
}

public struct KokoroSubscriptionDefaults: Codable, Sendable {
    public let format: String
    public let `protocol`: String
    public let plan: String?
    public let isp: String?
    public let mode: String
    public let ruleSource: String
    public let finalRoute: String
    public let ruleProviderAutoUpdate: Bool
    public let profileAutoUpdate: Bool
    public let profileUpdateHours: Int
}

public struct KokoroSubscriptionOptions: Codable, Sendable {
    public let formats: [KokoroFormatOption]
    public let protocols: [KokoroProtocolOption]
    public let plans: [KokoroPlan]
    public let isps: [KokoroISPOption]
    public let ruleSources: [String]
    public let finalRoutes: [String]
    public let profileUpdate: KokoroProfileUpdateRange
    public let defaults: KokoroSubscriptionDefaults
}

public struct KokoroResolveRequest: Codable, Sendable {
    public let format: String
    public let `protocol`: String
    public let plan: String?
    public let isp: String?
    public let mode: String
    public let ruleSource: String
    public let finalRoute: String
    public let ruleProviderAutoUpdate: Bool
    public let profileAutoUpdate: Bool
    public let profileUpdateHours: Int

    public init(
        protocol: String,
        plan: String?,
        isp: String?,
        mode: String,
        ruleSource: String,
        finalRoute: String,
        ruleProviderAutoUpdate: Bool,
        profileAutoUpdate: Bool,
        profileUpdateHours: Int
    ) {
        format = "sing-box"
        self.protocol = `protocol`
        self.plan = plan
        self.isp = isp
        self.mode = mode
        self.ruleSource = ruleSource
        self.finalRoute = finalRoute
        self.ruleProviderAutoUpdate = ruleProviderAutoUpdate
        self.profileAutoUpdate = profileAutoUpdate
        self.profileUpdateHours = profileUpdateHours
    }
}

public struct KokoroResolvedSubscription: Codable, Sendable {
    public let format: String
    public let contentType: String
    public let filename: String
    public let profileName: String
    public let authenticatedConfigUrl: String
}

public enum KokoroAPI {
    public static let redirectURI = "kokoro://oauth/callback"

    private static let baseURL = URL(string: "https://amamiyakoko.ro/api/")!
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    public static func loginURL(state: String) throws -> URL {
        var components = URLComponents(url: endpoint("app/auth/login"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components?.url else {
            throw KokoroAPIError.invalidResponse
        }
        return url
    }

    public static func currentUser() async throws -> KokoroUser {
        try await decodeAuthorized(KokoroUser.self, request: request(path: "app/me"))
    }

    public static func subscriptionOptions() async throws -> KokoroSubscriptionOptions {
        try await decodeAuthorized(KokoroSubscriptionOptions.self, request: request(path: "app/subscription/options"))
    }

    public static func resolveSubscription(_ settings: KokoroResolveRequest) async throws -> KokoroResolvedSubscription {
        var request = request(path: "app/subscription/resolve", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(settings)
        return try await decodeAuthorized(KokoroResolvedSubscription.self, request: request)
    }

    public static func downloadConfiguration(from urlString: String) async throws -> String {
        guard isAuthenticatedConfigurationURL(urlString), let url = URL(string: urlString) else {
            throw KokoroAPIError.invalidConfigurationURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        let (data, response) = try await KokoroSession.shared.authorizedData(for: request)
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        guard contentType.hasPrefix("application/json") else {
            throw KokoroAPIError.invalidContentType
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw KokoroAPIError.invalidResponse
        }
        return content
    }

    public static func isAuthenticatedConfigurationURL(_ urlString: String?) -> Bool {
        guard let urlString, let url = URL(string: urlString),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "amamiyakoko.ro",
              url.port == nil
        else {
            return false
        }
        return url.path == "/api/app/subscription/config"
    }

    fileprivate static func isAuthorizedAPIURL(_ url: URL?) -> Bool {
        guard let url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "amamiyakoko.ro",
              url.port == nil
        else {
            return false
        }
        return url.path.hasPrefix("/api/app/")
    }

    private static func decodeAuthorized<Value: Decodable>(_ type: Value.Type, request: URLRequest) async throws -> Value {
        let (data, _) = try await KokoroSession.shared.authorizedData(for: request)
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw KokoroAPIError.invalidResponse
        }
    }

    fileprivate static func endpoint(_ path: String) -> URL {
        URL(string: path, relativeTo: baseURL)!.absoluteURL
    }

    private static func request(path: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = method
        request.timeoutInterval = 30
        return request
    }
}

public actor KokoroSession {
    public static let shared = KokoroSession()

    private struct Credentials: Codable, Sendable {
        let accessToken: String
        let accessTokenExpiresAt: Date
        let refreshToken: String
        let refreshTokenExpiresAt: Date
    }

    private struct TokenRequest: Encodable {
        let grantType: String
        let code: String?
        let redirectURI: String?
        let refreshToken: String?
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int
        let refreshToken: String
        let refreshExpiresIn: Int
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private var credentials: Credentials?
    private var didLoadCredentials = false
    private var refreshTask: Task<Credentials, Error>?

    public func hasSession() -> Bool {
        loadCredentialsIfNeeded()
        return credentials != nil
    }

    public func exchangeAuthorizationCode(_ code: String) async throws {
        let tokenResponse = try await Self.requestToken(TokenRequest(
            grantType: "authorization_code",
            code: code,
            redirectURI: KokoroAPI.redirectURI,
            refreshToken: nil
        ))
        try replaceCredentials(with: tokenResponse)
    }

    public func authorizedData(for originalRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard KokoroAPI.isAuthorizedAPIURL(originalRequest.url) else {
            throw KokoroAPIError.invalidConfigurationURL
        }
        let accessToken = try await validAccessToken()
        var request = originalRequest
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        var result = try await Self.perform(request)

        if result.1.statusCode == 401 {
            let refreshed = try await credentialsAfterUnauthorized(rejectedAccessToken: accessToken)
            request.setValue("Bearer \(refreshed.accessToken)", forHTTPHeaderField: "Authorization")
            result = try await Self.perform(request)
            if result.1.statusCode == 401 {
                clearCredentials()
            }
        }

        try Self.validate(result)
        return result
    }

    public func revoke() async {
        loadCredentialsIfNeeded()
        defer { clearCredentials() }
        guard let credentials else { return }

        var request = URLRequest(url: KokoroAPI.endpoint("app/auth/revoke"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await Self.perform(request)
    }

    private func validAccessToken() async throws -> String {
        loadCredentialsIfNeeded()
        guard let credentials else {
            throw KokoroAPIError.noSession
        }
        if credentials.accessTokenExpiresAt > Date().addingTimeInterval(60) {
            return credentials.accessToken
        }
        return try await refresh(force: false).accessToken
    }

    private func credentialsAfterUnauthorized(rejectedAccessToken: String) async throws -> Credentials {
        loadCredentialsIfNeeded()
        guard let credentials else {
            throw KokoroAPIError.noSession
        }
        if credentials.accessToken != rejectedAccessToken {
            return credentials
        }
        return try await refresh(force: true)
    }

    private func refresh(force: Bool) async throws -> Credentials {
        loadCredentialsIfNeeded()
        guard let credentials else {
            throw KokoroAPIError.noSession
        }
        if !force, credentials.accessTokenExpiresAt > Date().addingTimeInterval(60) {
            return credentials
        }
        guard credentials.refreshTokenExpiresAt > Date() else {
            clearCredentials()
            throw KokoroAPIError.noSession
        }
        if let refreshTask {
            return try await refreshTask.value
        }

        let currentRefreshToken = credentials.refreshToken
        let task = Task {
            let response = try await Self.requestToken(TokenRequest(
                grantType: "refresh_token",
                code: nil,
                redirectURI: nil,
                refreshToken: currentRefreshToken
            ))
            return Self.credentials(from: response)
        }
        refreshTask = task
        do {
            let refreshed = try await task.value
            try KeychainStore.save(refreshed)
            self.credentials = refreshed
            refreshTask = nil
            return refreshed
        } catch {
            refreshTask = nil
            if case let KokoroAPIError.http(status, _) = error, status == 401 {
                clearCredentials()
            }
            throw error
        }
    }

    private func replaceCredentials(with response: TokenResponse) throws {
        let credentials = Self.credentials(from: response)
        try KeychainStore.save(credentials)
        self.credentials = credentials
        didLoadCredentials = true
    }

    private static func credentials(from response: TokenResponse) -> Credentials {
        Credentials(
            accessToken: response.accessToken,
            accessTokenExpiresAt: Date().addingTimeInterval(TimeInterval(max(response.expiresIn, 0))),
            refreshToken: response.refreshToken,
            refreshTokenExpiresAt: Date().addingTimeInterval(TimeInterval(max(response.refreshExpiresIn, 0)))
        )
    }

    private func loadCredentialsIfNeeded() {
        guard !didLoadCredentials else { return }
        didLoadCredentials = true
        do {
            credentials = try KeychainStore.load(Credentials.self)
        } catch {
            KeychainStore.delete()
            credentials = nil
        }
    }

    private func clearCredentials() {
        credentials = nil
        refreshTask?.cancel()
        refreshTask = nil
        didLoadCredentials = true
        KeychainStore.delete()
    }

    private static func requestToken(_ tokenRequest: TokenRequest) async throws -> TokenResponse {
        var request = URLRequest(url: KokoroAPI.endpoint("app/auth/token"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(tokenRequest)
        let result = try await perform(request)
        try validate(result)
        do {
            return try decoder.decode(TokenResponse.self, from: result.0)
        } catch {
            throw KokoroAPIError.invalidResponse
        }
    }

    private static func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(
            for: request,
            delegate: KokoroURLSessionDelegate.shared
        )
        guard let response = response as? HTTPURLResponse else {
            throw KokoroAPIError.invalidResponse
        }
        return (data, response)
    }

    private static func validate(_ result: (Data, HTTPURLResponse)) throws {
        guard (200 ..< 300).contains(result.1.statusCode) else {
            throw KokoroAPIError.http(status: result.1.statusCode, detail: errorDetail(from: result.0))
        }
    }

    private static func errorDetail(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = object["detail"]
        else {
            return nil
        }
        if let detail = detail as? String {
            return detail
        }
        if let validationErrors = detail as? [[String: Any]] {
            let messages = validationErrors.compactMap { $0["msg"] as? String }
            return messages.isEmpty ? nil : messages.joined(separator: "; ")
        }
        return nil
    }

    private enum KeychainStore {
        private static let service = "ro.amamiyakoko.sing-box.kokoro.session"
        private static let account = "tokens"

        static func save<Value: Encodable>(_ value: Value) throws {
            let data = try JSONEncoder().encode(value)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if updateStatus == errSecSuccess {
                return
            }
            guard updateStatus == errSecItemNotFound else {
                throw KokoroAPIError.keychain(status: updateStatus)
            }
            var addQuery = query
            for (key, value) in attributes {
                addQuery[key] = value
            }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KokoroAPIError.keychain(status: addStatus)
            }
        }

        static func load<Value: Decodable>(_ type: Value.Type) throws -> Value? {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecItemNotFound {
                return nil
            }
            guard status == errSecSuccess, let data = item as? Data else {
                throw KokoroAPIError.keychain(status: status)
            }
            return try JSONDecoder().decode(type, from: data)
        }

        static func delete() {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}
