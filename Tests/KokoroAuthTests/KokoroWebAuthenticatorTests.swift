import AuthenticationServices
import Foundation
import XCTest
@testable import KokoroAuth
@testable import KokoroWebAuth

@MainActor
private final class Browser: KokoroBrowserSession {
    var presentationContextProvider: (any ASWebAuthenticationPresentationContextProviding)?
    var prefersEphemeralWebBrowserSession = false
    var startResult = true
    var cancelled = false
    let url: URL
    let complete: (URL?, Error?) -> Void
    init(url: URL, complete: @escaping (URL?, Error?) -> Void) {
        self.url = url
        self.complete = complete
    }
    func start() -> Bool { startResult }
    func cancel() { cancelled = true }
    var callback: URL {
        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
        return URL(string: "kokoro://oauth/callback?state=\(state)&code=test-code")!
    }
}

final class KokoroWebAuthenticatorTests: XCTestCase {
    @MainActor
    func testCallbackRoutesOnceAndLateOldSessionCannotAffectNextLogin() async throws {
        var browsers: [Browser] = []
        var exchanges: [KokoroAuthorization] = []
        let auth = KokoroWebAuthenticator(makeSession: { url, completion in
            let browser = Browser(url: url, complete: completion)
            browsers.append(browser)
            return browser
        }, exchange: { exchanges.append($0) })
        let first = Task { try await auth.signIn() }
        while browsers.isEmpty { await Task.yield() }
        do { try await auth.signIn(); XCTFail("Concurrent login accepted") } catch {}
        XCTAssertTrue(auth.handleCallback(browsers[0].callback))
        browsers[0].complete(browsers[0].callback, nil)
        try await first.value
        XCTAssertEqual(exchanges.count, 1)
        XCTAssertFalse(auth.handleCallback(browsers[0].callback))
        let second = Task { try await auth.signIn() }
        while browsers.count < 2 { await Task.yield() }
        browsers[0].complete(browsers[0].callback, nil)
        XCTAssertTrue(auth.handleCallback(browsers[1].callback))
        try await second.value
        XCTAssertEqual(exchanges.count, 2)
        XCTAssertNotEqual(exchanges[0].codeVerifier, exchanges[1].codeVerifier)
        for i in 0 ..< 2 {
            let challenge = URLComponents(url: browsers[i].url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "code_challenge" }!.value!
            XCTAssertEqual(try KokoroPendingLogin.challenge(for: exchanges[i].codeVerifier), challenge)
            XCTAssertTrue(browsers[i].cancelled)
        }
    }

    @MainActor
    func testTaskCancellationClearsPendingLogin() async throws {
        var browser: Browser?
        let auth = KokoroWebAuthenticator(makeSession: {
            let value = Browser(url: $0, complete: $1); browser = value; return value
        }, exchange: { _ in XCTFail("Cancelled login exchanged") })
        let task = Task { try await auth.signIn() }
        while browser == nil { await Task.yield() }
        task.cancel()
        do { try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Wrong error") }
        XCTAssertTrue(browser!.cancelled)
        XCTAssertFalse(auth.handleCallback(browser!.callback))
    }

    @MainActor
    func testBrowserCancelFailureAndTimeoutClearPendingLogin() async throws {
        for scenario in ["cancel", "startFailure", "timeout", "invalid"] {
            var browser: Browser?
            let auth = KokoroWebAuthenticator(makeSession: {
                let value = Browser(url: $0, complete: $1)
                value.startResult = scenario != "startFailure"
                browser = value
                return value
            }, exchange: { _ in XCTFail("Failed login exchanged") },
            lifetimeNanoseconds: scenario == "timeout" ? 5_000_000 : 300_000_000_000)
            let task = Task { try await auth.signIn() }
            while browser == nil { await Task.yield() }
            if scenario == "cancel" {
                browser!.complete(nil, ASWebAuthenticationSessionError(.canceledLogin))
            } else if scenario == "invalid" {
                browser!.complete(URL(string: "kokoro://oauth:443/callback?state=x&code=x"), nil)
            }
            do { try await task.value; XCTFail("Expected rejection") } catch {}
            XCTAssertTrue(browser!.cancelled)
            XCTAssertFalse(auth.handleCallback(browser!.callback))
        }
    }

    @MainActor
    func testColdStartRejectsWithoutOpeningBrowserOrExchanging() {
        let auth = KokoroWebAuthenticator(makeSession: {
            XCTFail("Must restart through explicit login")
            return Browser(url: $0, complete: $1)
        }, exchange: { _ in XCTFail("Missing verifier") })
        XCTAssertFalse(auth.handleCallback(URL(string: "kokoro://oauth/callback?state=old&code=old")!))
    }
}
