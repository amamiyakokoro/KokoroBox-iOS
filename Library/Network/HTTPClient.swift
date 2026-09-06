import Foundation
import Libbox

public class HTTPClient {
    public static var defaultUserAgent: String {
        var userAgent = Variant.applicationName
        userAgent += " (sing-box "
        userAgent += LibboxVersion()
        userAgent += "; language "
        userAgent += Locale.current.identifier
        userAgent += ")"
        return userAgent
    }

    private let client: any LibboxHTTPClientProtocol

    public init() {
        client = LibboxNewHTTPClient()!
        client.modernTLS()
    }

    public func getString(_ url: String?, headers: [String: String] = [:], userAgent: String? = nil) throws -> String {
        #if DEBUG
            precondition(!Thread.isMainThread, "HTTPClient.getString(...) must not be called on the main thread")
        #endif
        let request = client.newRequest()!
        request.setUserAgent(try HTTPUserAgent.normalizeCustom(userAgent) ?? HTTPClient.defaultUserAgent)
        for (key, value) in headers {
            request.setHeader(key, value: value)
        }
        try request.setURL(url)
        let response = try request.execute()
        let content = try response.getContent()
        return content.value
    }

    public func getStringAsync(_ url: String?, userAgent: String? = nil) async throws -> String {
        try await Self.getStringAsync(url, userAgent: userAgent)
    }

    public static func getStringAsync(_ url: String?, userAgent: String? = nil) async throws -> String {
        try await BlockingIO.run {
            try HTTPClient().getString(url, userAgent: userAgent)
        }
    }

    public func writeTo(_ url: String?, path: String, userAgent: String? = nil, progress: ((Int64, Int64) -> Void)? = nil) throws {
        #if DEBUG
            precondition(!Thread.isMainThread, "HTTPClient.writeTo(...) must not be called on the main thread")
        #endif
        let request = client.newRequest()!
        request.setUserAgent(try HTTPUserAgent.normalizeCustom(userAgent) ?? HTTPClient.defaultUserAgent)
        try request.setURL(url)
        let response = try request.execute()
        if let progress {
            let handler = WriteToProgressHandler(progress)
            try response.writeTo(withProgress: path, handler: handler)
        } else {
            try response.write(to: path)
        }
    }

    public static func writeToAsync(_ url: String?, path: String, userAgent: String? = nil, progress: ((Int64, Int64) -> Void)? = nil) async throws {
        try await BlockingIO.run {
            try HTTPClient().writeTo(url, path: path, userAgent: userAgent, progress: progress)
        }
    }

    deinit {
        client.close()
    }
}

private class WriteToProgressHandler: NSObject, LibboxHTTPResponseWriteToProgressHandlerProtocol {
    private let handler: (Int64, Int64) -> Void

    init(_ handler: @escaping (Int64, Int64) -> Void) {
        self.handler = handler
    }

    func update(_ progress: Int64, total: Int64) {
        handler(progress, total)
    }
}
