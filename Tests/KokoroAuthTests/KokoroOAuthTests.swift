import Foundation
import XCTest
@testable import KokoroAuth

final class KokoroOAuthTests: XCTestCase {
    func testAppleURLSchemeRegistrations() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for target in ["SFI", "SFM", "SFM.System"] {
            let data = try Data(contentsOf: root.appendingPathComponent("\(target)/Info.plist"))
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
            let types = plist["CFBundleURLTypes"] as! [[String: Any]]
            XCTAssertTrue(types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains("kokoro") == true })
            if target != "SFI" { XCTAssertEqual(plist["LSMultipleInstancesProhibited"] as? Bool, true) }
        }
    }

    private func callback(_ state: String, extra: String = "code=test-code") -> URL {
        URL(string: "kokoro://oauth/callback?state=\(state)&\(extra)")!
    }

    func testRFC7636Vector() throws {
        let challenge = try KokoroPendingLogin.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertFalse(challenge.contains("="))
    }

    func testVerifierFormat() throws {
        for value in ["", String(repeating: "a", count: 42), String(repeating: "a", count: 129),
                      String(repeating: "é", count: 43), String(repeating: "+", count: 43),
                      String(repeating: "=", count: 43), String(repeating: "/", count: 43)] {
            XCTAssertThrowsError(try KokoroPendingLogin.challenge(for: value))
        }
        XCTAssertNoThrow(try KokoroPendingLogin.challenge(for: String(repeating: "~", count: 128)))
    }

    func testIndependentRandomSecretsAndLoginURL() throws {
        var secrets = Set<String>()
        for _ in 0 ..< 100 {
            let login = try KokoroPendingLogin()
            for secret in [login.state, login.codeVerifier] {
                XCTAssertEqual(secret.count, 43)
                XCTAssertNotNil(secret.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression))
                XCTAssertTrue(secrets.insert(secret).inserted)
            }
            let url = try login.loginURL()
            let c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            XCTAssertEqual(c.scheme, "https")
            XCTAssertEqual(c.host, "amamiyakoko.ro")
            XCTAssertEqual(c.path, "/api/app/auth/login")
            let query = Dictionary(uniqueKeysWithValues: c.queryItems!.map { ($0.name, $0.value!) })
            XCTAssertEqual(query, ["redirect_uri": "kokoro://oauth/callback", "state": login.state,
                                   "code_challenge": try KokoroPendingLogin.challenge(for: login.codeVerifier),
                                   "code_challenge_method": "S256"])
            XCTAssertFalse(url.absoluteString.contains(login.codeVerifier))
        }
    }

    func testSuccessConsumesMatchingVerifierAndRejectsReplay() throws {
        var transaction = KokoroLoginTransaction()
        let login = try transaction.begin()
        let url = callback(login.state)
        let authorization = try transaction.consume(url)
        XCTAssertEqual(authorization.code, "test-code")
        XCTAssertEqual(authorization.codeVerifier, login.codeVerifier)
        XCTAssertEqual(authorization.redirectURI, "kokoro://oauth/callback")
        XCTAssertThrowsError(try transaction.consume(url))
    }

    func testMissingWrongEmptyDuplicateAndExpiredState() throws {
        let time = Date()
        for query in ["code=x", "state=&code=x", "state=unknown&code=x", "state=%STATE%&state&code=x",
                      "state=%STATE%&state=%STATE%&code=x", "st%61te=%STATE%&state=%STATE%&code=x"] {
            var transaction = KokoroLoginTransaction()
            let login = try transaction.begin(now: time)
            let url = URL(string: "kokoro://oauth/callback?" + query.replacingOccurrences(of: "%STATE%", with: login.state))!
            XCTAssertThrowsError(try transaction.consume(url, now: time))
            XCTAssertThrowsError(try transaction.consume(callback(login.state), now: time))
        }
        var transaction = KokoroLoginTransaction()
        let login = try transaction.begin(now: time)
        XCTAssertThrowsError(try transaction.consume(callback(login.state), now: time.addingTimeInterval(300)))
    }

    func testForgedURIsAndDuplicateSecurityParameters() throws {
        let uris = ["other://oauth/callback", "kokoro://evil/callback", "kokoro://oauth/other",
                    "kokoro://oauth/callback/", "kokoro://oauth:443/callback", "kokoro://oauth:/callback",
                    "kokoro://user@oauth/callback", "kokoro://user:pass@oauth/callback", "kokoro://@oauth/callback",
                    "kokoro://oauth/%63allback", "kokoro://o%61uth/callback"]
        for uri in uris {
            var transaction = KokoroLoginTransaction()
            let login = try transaction.begin()
            XCTAssertThrowsError(try transaction.consume(URL(string: uri + "?state=\(login.state)&code=x")!), uri)
        }
        for extra in ["code=x#fragment", "code=x#", "code=x&code", "code=x&code=y",
                      "error=access_denied&error=access_denied", "code=x&error=denied",
                      "code=", "code", "error=", "error", "code=x&code_verifier=a&code_verifier=b",
                      "code=x&error_description=a&error_description=b", "code=x&redirect_uri=a&redirect_uri=b"] {
            var transaction = KokoroLoginTransaction()
            let login = try transaction.begin()
            XCTAssertThrowsError(try transaction.consume(callback(login.state, extra: extra)), extra)
        }
    }

    func testDenialAndUntrustedErrorText() throws {
        for extra in ["error=access_denied", "error=SECRET&error_description=SECRET&error_uri=SECRET"] {
            var transaction = KokoroLoginTransaction()
            let login = try transaction.begin()
            XCTAssertThrowsError(try transaction.consume(callback(login.state, extra: extra))) { error in
                XCTAssertFalse(error.localizedDescription.contains("SECRET"))
            }
            XCTAssertThrowsError(try transaction.consume(callback(login.state)))
        }
    }

    func testCancellationColdStartLostVerifierAndLoginIsolation() throws {
        var transaction = KokoroLoginTransaction()
        let a = try transaction.begin()
        XCTAssertThrowsError(try transaction.begin())
        transaction.cancel()
        XCTAssertThrowsError(try transaction.consume(callback(a.state)))
        let b = try transaction.begin()
        XCTAssertNotEqual(a.state, b.state)
        XCTAssertNotEqual(a.codeVerifier, b.codeVerifier)
        XCTAssertThrowsError(try transaction.consume(callback(a.state)))
        XCTAssertThrowsError(try transaction.consume(callback(b.state)))
        let c = try transaction.begin()
        XCTAssertEqual(try transaction.consume(callback(c.state)).codeVerifier, c.codeVerifier)
        // A new process has no pending record/verifier, even if it receives an otherwise valid URL.
        var restarted = KokoroLoginTransaction()
        XCTAssertThrowsError(try restarted.consume(callback(c.state)))
    }

    func testExpiredLoginCanBeReplaced() throws {
        var transaction = KokoroLoginTransaction()
        let time = Date()
        let old = try transaction.begin(now: time)
        let new = try transaction.begin(now: time.addingTimeInterval(301))
        XCTAssertNotEqual(old.codeVerifier, new.codeVerifier)
        XCTAssertEqual(try transaction.consume(callback(new.state), now: time.addingTimeInterval(302)).codeVerifier, new.codeVerifier)
    }
}
