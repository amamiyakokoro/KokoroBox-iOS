import Foundation
import XCTest
@testable import KokoroAuth

final class KokoroCustomRulesTests: XCTestCase {
    private let options = KokoroCustomRulesOptions(
        schemaVersion: 1,
        ruleTypes: ["DOMAIN-SUFFIX", "RULE-SET", "MATCH"],
        targets: ["DIRECT", "REJECT", "JP"],
        ruleProviders: [
            KokoroRuleProviderOption(name: "geosite-private", behavior: "domain"),
            KokoroRuleProviderOption(name: "geoip-private", behavior: "ipcidr"),
        ],
        limits: ["max_sets": 5, "max_rules_per_set": 3, "max_name_length": 64, "max_payload_length": 32]
    )

    func testStateDecodingPreservesRuleOrderAndRevision() throws {
        let data = Data(#"""
        {
          "schema_version": 1,
          "future_field": true,
          "sets": [{
            "id": 13,
            "name": "Games",
            "revision": 2,
            "created_at": "2026-09-05T09:00:00",
            "updated_at": "2026-09-05T09:30:00",
            "rules": []
          }, {
            "id": 12,
            "name": "DeFaUlT",
            "revision": 4,
            "created_at": "2026-09-05T10:00:00",
            "updated_at": "2026-09-05T11:30:00",
            "rules": [
              {"id": 52, "type": "MATCH", "payload": null, "target": "DIRECT", "priority": 1, "updated_at": "b"},
              {"id": 51, "type": "DOMAIN-SUFFIX", "payload": "example.com", "target": "JP", "priority": 0, "updated_at": "a"}
            ]
          }]
        }
        """#.utf8)
        let state = try KokoroAPI.decoder.decode(KokoroCustomRulesState.self, from: data)
        XCTAssertEqual(state.schemaVersion, 1)
        XCTAssertEqual(state.defaultRuleSet?.id, 12)
        XCTAssertEqual(state.defaultRuleSet?.revision, 4)
        XCTAssertEqual(state.defaultRuleSet?.rules.map(\.id), [52, 51])

        let stateWithoutVersion = try KokoroAPI.decoder.decode(
            KokoroCustomRulesState.self,
            from: Data(#"{"sets":[]}"#.utf8)
        )
        XCTAssertEqual(stateWithoutVersion.schemaVersion, 1)
    }

    func testReadAndDefaultRuleReplacementRequestsMatchContract() throws {
        XCTAssertRequest(KokoroAPI.customRulesStateRequest(), method: "GET", path: "/api/app/custom-rules")
        XCTAssertRequest(KokoroAPI.customRulesOptionsRequest(), method: "GET", path: "/api/app/custom-rules/options")

        let rules = [
            KokoroCustomRuleInput(type: "DOMAIN-SUFFIX", payload: "example.com", target: "DIRECT"),
            KokoroCustomRuleInput(type: "MATCH", payload: nil, target: "JP"),
        ]
        let replace = try KokoroAPI.replaceRulesRequest(setID: 12, expectedRevision: 4, rules: rules)
        XCTAssertRequest(replace, method: "PUT", path: "/api/app/custom-rules/sets/12/rules")
        let body = try JSONSerialization.jsonObject(with: replace.httpBody!) as! [String: Any]
        XCTAssertEqual(body["expected_revision"] as? Int, 4)
        let encodedRules = body["rules"] as! [[String: Any]]
        XCTAssertEqual(encodedRules[0] as NSDictionary,
                       ["type": "DOMAIN-SUFFIX", "payload": "example.com", "target": "DIRECT"] as NSDictionary)
        XCTAssertTrue(encodedRules[1]["payload"] is NSNull)
        XCTAssertNil(replace.value(forHTTPHeaderField: "Authorization"))
    }

    func testValidatorAcceptsDynamicOptionsAndValidOrder() throws {
        let rules = [
            KokoroCustomRuleInput(type: "RULE-SET", payload: "geosite-private", target: "REJECT"),
            KokoroCustomRuleInput(type: "DOMAIN-SUFFIX", payload: "example.com", target: "JP"),
            KokoroCustomRuleInput(type: "MATCH", payload: nil, target: "DIRECT"),
        ]
        XCTAssertNoThrow(try KokoroCustomRulesValidator.validate(rules, options: options))
        XCTAssertNoThrow(try KokoroCustomRulesValidator.validate(
            [.init(type: "DOMAIN-SUFFIX", payload: "internal space", target: "DIRECT")],
            options: options
        ))
    }

    func testValidatorRejectsUnsafeOrStaleRulesWithoutEchoingPayload() throws {
        let cases: [([KokoroCustomRuleInput], KokoroCustomRulesValidationError)] = [
            ([.init(type: "DOMAIN", payload: "secret.example", target: "DIRECT")], .unsupportedType),
            ([.init(type: "DOMAIN-SUFFIX", payload: "secret.example", target: "US")], .unsupportedTarget),
            ([.init(type: "DOMAIN-SUFFIX", payload: nil, target: "DIRECT")], .payloadRequired),
            ([.init(type: "DOMAIN-SUFFIX", payload: " secret.example", target: "DIRECT")], .invalidCharacters),
            ([.init(type: "DOMAIN-SUFFIX", payload: "secret.example,DIRECT", target: "DIRECT")], .invalidCharacters),
            ([.init(type: "RULE-SET", payload: "geoip-private", target: "DIRECT")], .invalidProvider),
            ([.init(type: "MATCH", payload: nil, target: "REJECT")], .matchCannotReject),
            ([.init(type: "MATCH", payload: nil, target: "DIRECT"),
              .init(type: "DOMAIN-SUFFIX", payload: "secret.example", target: "DIRECT")], .matchMustBeLast),
            ([.init(type: "DOMAIN-SUFFIX", payload: "secret.example", target: "DIRECT"),
              .init(type: "MATCH", payload: nil, target: "DIRECT"),
              .init(type: "MATCH", payload: nil, target: "DIRECT")], .duplicateMatch),
        ]
        for (rules, expected) in cases {
            XCTAssertThrowsError(try KokoroCustomRulesValidator.validate(rules, options: options)) { error in
                XCTAssertEqual(error as? KokoroCustomRulesValidationError, expected)
                XCTAssertFalse(error.localizedDescription.contains("secret.example"))
            }
        }
    }

    func testMatchEmptyPayloadEqualsServerNullAfterUnknownResult() throws {
        let data = Data(#"""
        {"id":12,"name":"default","revision":5,"created_at":"a","updated_at":"b","rules":[
          {"id":99,"type":"MATCH","payload":null,"target":"DIRECT","priority":0,"updated_at":"b"}
        ]}
        """#.utf8)
        let set = try KokoroAPI.decoder.decode(KokoroRuleSet.self, from: data)
        XCTAssertTrue(set.hasSameRules(as: [.init(type: "MATCH", payload: "", target: "DIRECT")]))
    }

    func testConflictAndRateLimitErrorsKeepStructuredMetadata() throws {
        let url = URL(string: "https://amamiyakoko.ro/api/app/custom-rules")!
        let conflict = HTTPURLResponse(url: url, statusCode: 409, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try KokoroSession.validate((
            Data(#"{"detail":{"message":"changed","current_revision":9}}"#.utf8), conflict
        ))) { error in
            guard case let KokoroAPIError.conflict(revision) = error else { return XCTFail("Wrong error") }
            XCTAssertEqual(revision, 9)
        }

        let limited = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "12"])!
        XCTAssertThrowsError(try KokoroSession.validate((Data(), limited))) { error in
            guard case let KokoroAPIError.rateLimited(delay) = error else { return XCTFail("Wrong error") }
            XCTAssertEqual(delay, 12)
        }
    }

    private func XCTAssertRequest(
        _ request: URLRequest,
        method: String,
        path: String,
        json: [String: Any]? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(request.url?.scheme, "https", file: file, line: line)
        XCTAssertEqual(request.url?.host, "amamiyakoko.ro", file: file, line: line)
        XCTAssertEqual(request.url?.port, nil, file: file, line: line)
        XCTAssertEqual(request.url?.path, path, file: file, line: line)
        XCTAssertEqual(request.httpMethod, method, file: file, line: line)
        if let json {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json", file: file, line: line)
            let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! NSDictionary
            XCTAssertEqual(body, json as NSDictionary, file: file, line: line)
        }
    }
}
