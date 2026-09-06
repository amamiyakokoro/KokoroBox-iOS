import XCTest
@testable import KokoroAuth

final class HTTPUserAgentTests: XCTestCase {
    func testEmptyValueUsesDefault() throws {
        XCTAssertNil(try HTTPUserAgent.normalizeCustom(nil))
        XCTAssertNil(try HTTPUserAgent.normalizeCustom(""))
        XCTAssertNil(try HTTPUserAgent.normalizeCustom("  \n "))
    }

    func testCustomValueIsTrimmed() throws {
        XCTAssertEqual(try HTTPUserAgent.normalizeCustom("  Example/1.0  "), "Example/1.0")
        XCTAssertEqual(try HTTPUserAgent.normalizeCustom("KokoroBox custom"), "KokoroBox custom")
    }

    func testControlCharactersAreRejected() {
        for value in ["Example\nInjected", "Example\rInjected", "Example\tInjected", "Example\u{7F}Injected"] {
            XCTAssertThrowsError(try HTTPUserAgent.normalizeCustom(value))
        }
    }

    func testLengthLimit() throws {
        XCTAssertNotNil(try HTTPUserAgent.normalizeCustom(String(repeating: "a", count: 512)))
        XCTAssertThrowsError(try HTTPUserAgent.normalizeCustom(String(repeating: "a", count: 513)))
    }
}
