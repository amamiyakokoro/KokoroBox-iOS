import Foundation
import Network

public struct PublicIPInfo: Equatable, Sendable {
    public let address: String
    public let countryCode: String?

    public init(address: String, countryCode: String?) {
        self.address = address
        self.countryCode = countryCode
    }
}

public struct PublicIPInfoService: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let endpoints: [URL]
    private let transport: Transport

    public init() {
        self.init(
            endpoints: Self.defaultEndpoints,
            transport: { request in
                try await Self.session.data(for: request)
            }
        )
    }

    init(endpoints: [URL], transport: @escaping Transport) {
        self.endpoints = endpoints
        self.transport = transport
    }

    public func fetch() async throws -> PublicIPInfo {
        var lastError: Error = PublicIPInfoError.noAvailableEndpoint

        for endpoint in endpoints {
            do {
                return try await fetch(endpoint)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    private func fetch(_ endpoint: URL) async throws -> PublicIPInfo {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = Self.requestTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("KokoroBox-Apple", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await transport(request)
        guard let response = response as? HTTPURLResponse,
              (200 ..< 300).contains(response.statusCode),
              data.count <= Self.maximumResponseBytes
        else {
            throw PublicIPInfoError.invalidResponse
        }

        let payload = try Self.decoder.decode(APIResponse.self, from: data)
        let address = payload.ip?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard address.utf8.count <= 45,
              IPv4Address(address) != nil || IPv6Address(address) != nil
        else {
            throw PublicIPInfoError.invalidResponse
        }

        return PublicIPInfo(
            address: address,
            countryCode: Self.normalizeCountryCode(payload.countryCode ?? payload.country)
        )
    }

    private static func normalizeCountryCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.utf8.count == 2,
              code.utf8.allSatisfy({ byte in
                  byte >= Character("A").asciiValue! && byte <= Character("Z").asciiValue!
              })
        else {
            return nil
        }
        return code
    }

    private struct APIResponse: Decodable {
        let ip: String?
        let countryCode: String?
        let country: String?

        private enum CodingKeys: String, CodingKey {
            case ip
            case countryCode = "country_code"
            case country
        }
    }

    private static let requestTimeout: TimeInterval = 5
    private static let maximumResponseBytes = 64 * 1024
    private static let decoder = JSONDecoder()
    private static let defaultEndpoints = [
        URL(string: "https://api.ip.sb/geoip")!,
        URL(string: "https://ipapi.co/json/")!,
        URL(string: "https://api64.ipify.org?format=json")!,
    ]
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        return URLSession(configuration: configuration)
    }()
}

private enum PublicIPInfoError: Error {
    case invalidResponse
    case noAvailableEndpoint
}
