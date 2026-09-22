import Foundation
import XCTest
@testable import KokoroAuth

final class PublicIPInfoServiceTests: XCTestCase {
    func testNormalizesCountryCodeAndValidatesIPAddress() async throws {
        let endpoint = URL(string: "https://ip.example/geoip")!
        let service = PublicIPInfoService(endpoints: [endpoint]) { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            let data = Data(#"{"ip":" 203.0.113.1 ","country_code":" tw "}"#.utf8)
            return (data, self.response(endpoint, status: 200))
        }

        let info = try await service.fetch()
        XCTAssertEqual(info, PublicIPInfo(address: "203.0.113.1", countryCode: "TW"))
    }

    func testFallsBackToNextEndpoint() async throws {
        let invalid = URL(string: "https://invalid.example/geoip")!
        let valid = URL(string: "https://valid.example/geoip")!
        let service = PublicIPInfoService(endpoints: [invalid, valid]) { request in
            if request.url == invalid {
                return (Data("not-json".utf8), self.response(invalid, status: 200))
            }
            let data = Data(#"{"ip":"2001:db8::1","country":"jp"}"#.utf8)
            return (data, self.response(valid, status: 200))
        }

        let info = try await service.fetch()
        XCTAssertEqual(info, PublicIPInfo(address: "2001:db8::1", countryCode: "JP"))
    }

    func testAcceptsIPOnlyFallbackAndRejectsInvalidCountryCode() async throws {
        let endpoint = URL(string: "https://ip.example/json")!
        let service = PublicIPInfoService(endpoints: [endpoint]) { _ in
            let data = Data(#"{"ip":"203.0.113.2","country_code":"Taiwan"}"#.utf8)
            return (data, self.response(endpoint, status: 200))
        }

        let info = try await service.fetch()
        XCTAssertEqual(info, PublicIPInfo(address: "203.0.113.2", countryCode: nil))
    }

    private func response(_ url: URL, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}
