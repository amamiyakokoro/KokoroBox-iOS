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

    func testKokoroSubscriptionRequestsUseVersionedClientUserAgent() {
        XCTAssertEqual(KokoroAPI.subscriptionUserAgent(version: "1.14.4"), "KokoroBox-iOS/1.14.4")

        let request = KokoroAPI.subscriptionRequest(
            path: "app/subscription/resolve",
            method: "POST",
            appVersion: "1.14.4"
        )
        XCTAssertRequest(request, method: "POST", path: "/api/app/subscription/resolve")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "KokoroBox-iOS/1.14.4")
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

    func testConnectionSuggestionsPreferDomainSuffixAndAvailableRoutingGroup() throws {
        let options = connectionOptions()
        let source = KokoroConnectionRuleSource(
            domain: "API.Example.COM.", destination: "203.0.113.10:443", preferredTargets: ["unknown-node", "JP"]
        )
        XCTAssertEqual(source.suggestions(options: options), [
            .init(type: "DOMAIN-SUFFIX", payload: "example.com", target: "JP"),
            .init(type: "DOMAIN", payload: "api.example.com", target: "JP"),
            .init(type: "IP-CIDR", payload: "203.0.113.10/32", target: "JP"),
        ])
    }

    func testConnectionSuggestionsHandleIPv6AndServerCapabilities() {
        for destination in ["[2001:db8::1]:443", "2001:db8::1"] {
            let source = KokoroConnectionRuleSource(domain: "", destination: destination, preferredTargets: ["removed"])
            XCTAssertEqual(source.suggestions(options: connectionOptions()), [
                .init(type: "IP-CIDR6", payload: "2001:db8::1/128", target: "DIRECT"),
            ])
            XCTAssertTrue(source.suggestions(options: options).isEmpty)
        }
        let source = KokoroConnectionRuleSource(domain: "example.com", destination: "", preferredTargets: [])
        XCTAssertEqual(source.suggestions(options: options), [
            .init(type: "DOMAIN-SUFFIX", payload: "example.com", target: "DIRECT"),
        ])
        let domainOnly = KokoroCustomRulesOptions(ruleTypes: ["DOMAIN"], targets: ["DIRECT"], ruleProviders: [], limits: [:])
        XCTAssertEqual(source.suggestions(options: domainOnly), [
            .init(type: "DOMAIN", payload: "example.com", target: "DIRECT"),
        ])
        XCTAssertTrue(source.suggestions(options: connectionOptions(targets: [])).isEmpty)
        XCTAssertTrue(KokoroConnectionRuleSource(domain: "", destination: "invalid:443", preferredTargets: [])
            .suggestions(options: connectionOptions()).isEmpty)
        XCTAssertTrue(KokoroConnectionRuleSource(domain: "bad,host", destination: "", preferredTargets: [])
            .suggestions(options: connectionOptions()).isEmpty)
    }

    func testDomainSuffixUsesPublicSuffixListIncludingPrivateAndExceptionRules() {
        let cases = [
            ("api.example.com", "example.com"),
            ("a.b.example.co.uk", "example.co.uk"),
            ("api.example.com.tw", "example.com.tw"),
            ("cdn.user.github.io", "user.github.io"),
            ("a.b.ck", "a.b.ck"),
            ("a.www.ck", "www.ck"),
            ("www.city.kawasaki.jp", "city.kawasaki.jp"),
            ("api.example.internal", "example.internal"),
            ("www.食狮.公司.cn", "xn--85x722f.xn--55qx5d.cn"),
            ("www.xn--85x722f.xn--55qx5d.cn", "xn--85x722f.xn--55qx5d.cn"),
        ]
        for (hostname, expected) in cases {
            XCTAssertEqual(KokoroDomainSuffix.registrableDomain(hostname), expected, hostname)
            let source = KokoroConnectionRuleSource(domain: hostname, destination: "", preferredTargets: [])
            let suggestions = source.suggestions(options: connectionOptions())
            XCTAssertEqual(suggestions.first?.type, "DOMAIN-SUFFIX")
            XCTAssertEqual(suggestions.first?.payload, expected)
            XCTAssertEqual(suggestions.last?.payload, hostname)
        }
        for hostname in ["com", "co.uk", "github.io", "b.ck", "localhost", "bad..example.com", "bad/host.com", "bad,host.example.com"] {
            XCTAssertNil(KokoroDomainSuffix.registrableDomain(hostname), hostname)
        }
    }

    func testConnectionIPLiteralIsNotSuggestedAsDomain() {
        let source = KokoroConnectionRuleSource(domain: "203.0.113.10", destination: "203.0.113.10", preferredTargets: [])
        XCTAssertEqual(source.suggestions(options: connectionOptions()), [
            .init(type: "IP-CIDR", payload: "203.0.113.10/32", target: "DIRECT"),
        ])
    }

    func testConnectionRuleTakesPrecedenceAndKeepsMatchLast() throws {
        let connectionRule = KokoroCustomRuleInput(type: "DOMAIN-SUFFIX", payload: "example.com", target: "JP")
        let broadRule = KokoroCustomRuleInput(type: "DOMAIN-SUFFIX", payload: "com", target: "DIRECT")
        let match = KokoroCustomRuleInput(type: "MATCH", payload: nil, target: "DIRECT")
        XCTAssertEqual(try KokoroCustomRulesValidator.prepending(connectionRule, to: [broadRule, match], options: options),
                       [connectionRule, broadRule, match])
        // Moving an existing identical rule works even at the server's rule-count limit.
        XCTAssertEqual(try KokoroCustomRulesValidator.prepending(connectionRule, to: [broadRule, connectionRule, match], options: options),
                       [connectionRule, broadRule, match])
        let other = KokoroCustomRuleInput(type: "DOMAIN-SUFFIX", payload: "other.net", target: "DIRECT")
        XCTAssertThrowsError(try KokoroCustomRulesValidator.prepending(connectionRule, to: [broadRule, other, match], options: options)) { error in
            XCTAssertEqual(error as? KokoroCustomRulesValidationError, .tooManyRules)
        }
    }

    private func connectionOptions(targets: [String] = ["DIRECT", "JP"]) -> KokoroCustomRulesOptions {
        KokoroCustomRulesOptions(
            ruleTypes: ["DOMAIN", "DOMAIN-SUFFIX", "IP-CIDR", "IP-CIDR6", "MATCH"],
            targets: targets, ruleProviders: [], limits: [:]
        )
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
