import Foundation
import XCTest
@testable import KokoroAuth

private final class MemoryStore: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: KokoroSession.Credentials?
    var failSave = false
    func load() -> KokoroSession.Credentials? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
    func save(_ value: KokoroSession.Credentials) throws {
        lock.lock(); defer { lock.unlock() }
        if failSave { throw KokoroAPIError.keychain(status: -1) }
        stored = value
    }
    func delete() {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}

private actor MockHTTP {
    var requests: [URLRequest] = []
    let tokenStatus: Int
    let store: MemoryStore
    let rejectOldAccess: Bool
    init(store: MemoryStore, tokenStatus: Int = 200, rejectOldAccess: Bool = false) {
        self.store = store
        self.tokenStatus = tokenStatus
        self.rejectOldAccess = rejectOldAccess
    }
    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let isToken = request.url!.path.hasSuffix("/token")
        let status: Int
        let data: Data
        if isToken {
            // Ensure concurrent protected requests overlap while refreshing.
            try await Task.sleep(nanoseconds: 20_000_000)
            status = tokenStatus
            data = Data((status == 200
                ? "{\"access_token\":\"new-access\",\"refresh_token\":\"new-refresh\",\"expires_in\":3600,\"refresh_expires_in\":2592000}"
                : "{\"detail\":\"SECRET verifier/code/token may be echoed here\"}").utf8)
        } else {
            let access = request.value(forHTTPHeaderField: "Authorization")
            status = rejectOldAccess && access == "Bearer old-access" ? 401 : 200
            if access == "Bearer new-access" {
                // Waiting API requests must not proceed until the rotated pair is saved.
                XCTAssertEqual(store.load()?.accessToken, "new-access")
                XCTAssertEqual(store.load()?.refreshToken, "new-refresh")
            }
            data = Data("{}".utf8)
        }
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private actor FixedStatusHTTP {
    private(set) var requests: [URLRequest] = []
    let status: Int

    init(status: Int) {
        self.status = status
    }

    func perform(_ request: URLRequest) -> (Data, HTTPURLResponse) {
        requests.append(request)
        let data = status == 409
            ? Data(#"{"detail":{"message":"changed","current_revision":2}}"#.utf8)
            : Data(#"{"detail":"rejected"}"#.utf8)
        let headers = status == 429 ? ["Retry-After": "3"] : nil
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
}

final class KokoroSessionTests: XCTestCase {
    private func session(store: MemoryStore, http: MockHTTP) -> KokoroSession {
        KokoroSession(transport: { try await http.perform($0) }, load: { store.load() },
                      save: { try store.save($0) }, delete: { store.delete() })
    }

    private func authorization() throws -> KokoroAuthorization {
        var transaction = KokoroLoginTransaction()
        let login = try transaction.begin()
        return try transaction.consume(URL(string: "kokoro://oauth/callback?state=\(login.state)&code=test-code")!)
    }

    private func seed(_ store: MemoryStore, expired: Bool = true) throws {
        try store.save(.init(accessToken: "old-access", accessTokenExpiresAt: Date().addingTimeInterval(expired ? -1 : 3600),
                             refreshToken: "old-refresh", refreshTokenExpiresAt: Date().addingTimeInterval(3600)))
    }

    func testAuthorizationPOSTContainsOriginalVerifierAndPersistsTokens() async throws {
        let store = MemoryStore(), auth = try authorization()
        let http = MockHTTP(store: store)
        let client = session(store: store, http: http)
        try await client.exchangeAuthorizationCode(auth)
        let requests = await http.requests
        XCTAssertEqual(requests.count, 1)
        let request = requests[0]
        XCTAssertEqual(request.url?.absoluteString, "https://amamiyakoko.ro/api/app/auth/token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
        XCTAssertEqual(body, ["grant_type": "authorization_code", "code": "test-code",
                              "redirect_uri": "kokoro://oauth/callback", "code_verifier": auth.codeVerifier])
        XCTAssertEqual(store.load()?.accessToken, "new-access")
        XCTAssertEqual(store.load()?.refreshToken, "new-refresh")
        XCTAssertGreaterThan(store.load()!.accessTokenExpiresAt.timeIntervalSinceNow, 3500)
        XCTAssertGreaterThan(store.load()!.refreshTokenExpiresAt.timeIntervalSinceNow, 2591900)
    }

    func test400And422NeverRetryOrDowngradeOrExposeResponse() async throws {
        for status in [400, 422] {
            let store = MemoryStore(), http = MockHTTP(store: MemoryStore(), tokenStatus: status)
            let client = session(store: store, http: http)
            do {
                try await client.exchangeAuthorizationCode(authorization())
                XCTFail("Expected token rejection")
            } catch {
                guard case let KokoroAPIError.http(code, detail) = error else { return XCTFail("Unexpected error") }
                XCTAssertEqual(code, status)
                XCTAssertNil(detail)
                XCTAssertFalse(error.localizedDescription.contains("SECRET"))
            }
            let requests = await http.requests
            XCTAssertEqual(requests.count, 1)
            let body = try JSONSerialization.jsonObject(with: requests[0].httpBody!) as! [String: String]
            XCTAssertNotNil(body["code_verifier"])
            XCTAssertNil(store.load())
        }
    }

    func testRefreshSingleFlightPersistsBeforeReleasingWaiters() async throws {
        for unauthorized in [false, true] {
            let store = MemoryStore()
            try seed(store, expired: !unauthorized)
            let http = MockHTTP(store: store, rejectOldAccess: unauthorized)
            let client = session(store: store, http: http)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0 ..< 16 {
                    group.addTask {
                        _ = try await client.authorizedData(for: URLRequest(url: URL(string: "https://amamiyakoko.ro/api/app/me")!))
                    }
                }
                try await group.waitForAll()
            }
            let requests = await http.requests
            let refreshes = requests.filter { $0.url!.path.hasSuffix("/token") }
            XCTAssertEqual(refreshes.count, 1)
            let body = try JSONSerialization.jsonObject(with: refreshes[0].httpBody!) as! [String: String]
            XCTAssertEqual(body, ["grant_type": "refresh_token", "refresh_token": "old-refresh"])
            XCTAssertEqual(store.load()?.refreshToken, "new-refresh")
        }
    }

    func testRefresh401ClearsCredentials() async throws {
        let store = MemoryStore()
        try seed(store)
        let http = MockHTTP(store: store, tokenStatus: 401)
        let client = session(store: store, http: http)
        do {
            _ = try await client.authorizedData(for: URLRequest(url: URL(string: "https://amamiyakoko.ro/api/app/me")!))
            XCTFail("Expected refresh rejection")
        } catch {}
        XCTAssertNil(store.load())
        let hasSession = await client.hasSession()
        XCTAssertFalse(hasSession)
        let requests = await http.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testStorageFailureBlocksAllWaitingRequests() async throws {
        let store = MemoryStore()
        try seed(store)
        store.failSave = true
        let http = MockHTTP(store: store)
        let client = session(store: store, http: http)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 12 {
                group.addTask {
                    do {
                        _ = try await client.authorizedData(for: URLRequest(url: URL(string: "https://amamiyakoko.ro/api/app/me")!))
                        XCTFail("API request must wait for durable tokens")
                    } catch {}
                }
            }
        }
        let requests = await http.requests
        XCTAssertTrue(requests.allSatisfy { $0.url!.path.hasSuffix("/token") })
        XCTAssertEqual(store.load()?.accessToken, "old-access")
        XCTAssertEqual(store.load()?.refreshToken, "old-refresh")
    }

    func testLogoutDuringRefreshCannotRestoreSession() async throws {
        let store = MemoryStore()
        try seed(store)
        let http = MockHTTP(store: store)
        let client = session(store: store, http: http)
        let request = Task {
            try await client.authorizedData(for: URLRequest(url: URL(string: "https://amamiyakoko.ro/api/app/me")!))
        }
        while await http.requests.isEmpty { await Task.yield() }
        await client.revoke()
        _ = try? await request.value
        XCTAssertNil(store.load())
        let hasSession = await client.hasSession()
        XCTAssertFalse(hasSession)
    }

    func testLogoutOrCancellationDuringCodeExchangeCannotSaveTokens() async throws {
        for cancel in [false, true] {
            let store = MemoryStore()
            let http = MockHTTP(store: store)
            let client = session(store: store, http: http)
            let auth = try authorization()
            let request = Task { try await client.exchangeAuthorizationCode(auth) }
            while await http.requests.isEmpty { await Task.yield() }
            if cancel { request.cancel() } else { await client.revoke() }
            do { try await request.value; XCTFail("Abandoned exchange saved tokens") } catch {}
            XCTAssertNil(store.load())
        }
    }

    func testProtectedMutationDoesNotRetryNon401Errors() async throws {
        for status in [400, 409, 422, 429] {
            let store = MemoryStore()
            try seed(store, expired: false)
            let http = FixedStatusHTTP(status: status)
            let client = KokoroSession(
                transport: { await http.perform($0) },
                load: { store.load() },
                save: { try store.save($0) },
                delete: { store.delete() }
            )
            var request = URLRequest(url: URL(string: "https://amamiyakoko.ro/api/app/custom-rules/sets/12/rules")!)
            request.httpMethod = "PUT"
            do {
                _ = try await client.authorizedData(for: request)
                XCTFail("Expected HTTP \(status)")
            } catch {}
            let requests = await http.requests
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer old-access")
            XCTAssertEqual(store.load()?.refreshToken, "old-refresh")
        }
    }
}
