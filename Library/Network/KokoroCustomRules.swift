import Foundation

public struct KokoroCustomRulesState: Codable, Sendable {
    public let schemaVersion: Int
    public let sets: [KokoroRuleSet]

    public var defaultRuleSet: KokoroRuleSet? {
        sets.first(where: \.isDefault)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case sets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        sets = try container.decode([KokoroRuleSet].self, forKey: .sets)
    }
}

public struct KokoroRuleProviderOption: Codable, Hashable, Sendable {
    public let name: String
    public let behavior: String
}

public struct KokoroCustomRulesOptions: Codable, Sendable {
    public let schemaVersion: Int
    public let ruleTypes: [String]
    public let targets: [String]
    public let ruleProviders: [KokoroRuleProviderOption]
    public let limits: [String: Int]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case ruleTypes
        case targets
        case ruleProviders
        case limits
    }

    public init(
        schemaVersion: Int = 1,
        ruleTypes: [String],
        targets: [String],
        ruleProviders: [KokoroRuleProviderOption],
        limits: [String: Int]
    ) {
        self.schemaVersion = schemaVersion
        self.ruleTypes = ruleTypes
        self.targets = targets
        self.ruleProviders = ruleProviders
        self.limits = limits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        ruleTypes = try container.decode([String].self, forKey: .ruleTypes)
        targets = try container.decode([String].self, forKey: .targets)
        ruleProviders = try container.decode([KokoroRuleProviderOption].self, forKey: .ruleProviders)
        limits = try container.decode([String: Int].self, forKey: .limits)
    }

    public var maximumRulesPerSet: Int { limit(named: ["max_rules_per_set"], fallback: 200) }
    public var maximumPayloadLength: Int { limit(named: ["max_payload_length"], fallback: 1024) }

    public var domainRuleProviders: [KokoroRuleProviderOption] {
        ruleProviders.filter { $0.behavior.caseInsensitiveCompare("domain") == .orderedSame }
    }

    private func limit(named names: [String], fallback: Int) -> Int {
        names.lazy.compactMap { limits[$0] }.first(where: { $0 > 0 }) ?? fallback
    }
}

public struct KokoroRuleSet: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let revision: Int
    public let createdAt: String
    public let updatedAt: String
    public let rules: [KokoroCustomRule]

    public var isDefault: Bool { name.caseInsensitiveCompare("default") == .orderedSame }

    public func hasSameRules(as inputs: [KokoroCustomRuleInput]) -> Bool {
        guard rules.count == inputs.count else { return false }
        return zip(rules, inputs).allSatisfy { rule, input in
            rule.type == input.type
                && normalizedPayload(rule.payload, type: rule.type) == normalizedPayload(input.payload, type: input.type)
                && rule.target == input.target
        }
    }

    private func normalizedPayload(_ payload: String?, type: String) -> String? {
        type == "MATCH" && (payload?.isEmpty ?? true) ? nil : payload
    }
}

public struct KokoroCustomRule: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let type: String
    public let payload: String?
    public let target: String
    public let priority: Int
    public let updatedAt: String

    public var input: KokoroCustomRuleInput {
        KokoroCustomRuleInput(type: type, payload: payload, target: target)
    }
}

public struct KokoroCustomRuleInput: Codable, Hashable, Sendable {
    public var type: String
    public var payload: String?
    public var target: String

    public init(type: String, payload: String?, target: String) {
        self.type = type
        self.payload = payload
        self.target = target
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
        case target
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        if let payload {
            try container.encode(payload, forKey: .payload)
        } else {
            try container.encodeNil(forKey: .payload)
        }
        try container.encode(target, forKey: .target)
    }
}

public enum KokoroCustomRulesValidationError: LocalizedError, Equatable, Sendable {
    case tooManyRules
    case unsupportedType
    case unsupportedTarget
    case payloadRequired
    case payloadTooLong
    case invalidCharacters
    case invalidProvider
    case duplicateMatch
    case matchMustBeLast
    case matchCannotReject

    public var errorDescription: String? {
        switch self {
        case .tooManyRules: String(localized: "This rule set contains too many rules.")
        case .unsupportedType: String(localized: "The selected rule type is no longer available.")
        case .unsupportedTarget: String(localized: "The selected rule target is no longer available.")
        case .payloadRequired: String(localized: "This rule requires a value.")
        case .payloadTooLong: String(localized: "The rule value is too long.")
        case .invalidCharacters: String(localized: "Rule values and targets cannot contain surrounding whitespace, commas, or control characters.")
        case .invalidProvider: String(localized: "Select an available domain rule provider.")
        case .duplicateMatch: String(localized: "A rule set can contain only one MATCH rule.")
        case .matchMustBeLast: String(localized: "The MATCH rule must be last.")
        case .matchCannotReject: String(localized: "A MATCH rule cannot use the REJECT target.")
        }
    }
}

public enum KokoroCustomRulesValidator {
    public static func validate(_ rules: [KokoroCustomRuleInput], options: KokoroCustomRulesOptions) throws {
        guard rules.count <= options.maximumRulesPerSet else {
            throw KokoroCustomRulesValidationError.tooManyRules
        }
        let matchIndices = rules.indices.filter { rules[$0].type == "MATCH" }
        guard matchIndices.count <= 1 else { throw KokoroCustomRulesValidationError.duplicateMatch }
        if let matchIndex = matchIndices.first, matchIndex != rules.indices.last {
            throw KokoroCustomRulesValidationError.matchMustBeLast
        }
        for (index, rule) in rules.enumerated() {
            guard options.ruleTypes.contains(rule.type) else {
                throw KokoroCustomRulesValidationError.unsupportedType
            }
            guard options.targets.contains(rule.target) else {
                throw KokoroCustomRulesValidationError.unsupportedTarget
            }
            guard rule.target == rule.target.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rule.target.isEmpty,
                  rule.target.count <= 128,
                  !containsForbiddenCharacters(rule.target)
            else {
                throw KokoroCustomRulesValidationError.invalidCharacters
            }

            if rule.type == "MATCH" {
                guard index == rules.indices.last else { throw KokoroCustomRulesValidationError.matchMustBeLast }
                guard rule.payload?.isEmpty ?? true else { throw KokoroCustomRulesValidationError.invalidCharacters }
                guard rule.target != "REJECT" else { throw KokoroCustomRulesValidationError.matchCannotReject }
                continue
            }

            guard let payload = rule.payload, !payload.isEmpty else {
                throw KokoroCustomRulesValidationError.payloadRequired
            }
            guard payload.count <= options.maximumPayloadLength else {
                throw KokoroCustomRulesValidationError.payloadTooLong
            }
            guard payload == payload.trimmingCharacters(in: .whitespacesAndNewlines),
                  !containsForbiddenCharacters(payload)
            else {
                throw KokoroCustomRulesValidationError.invalidCharacters
            }
            if rule.type == "RULE-SET",
               !options.domainRuleProviders.contains(where: { $0.name == payload }) {
                throw KokoroCustomRulesValidationError.invalidProvider
            }
        }
    }

    private static func containsForbiddenCharacters(_ value: String) -> Bool {
        value.contains(",") || value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}

extension KokoroAPI {
    private struct RuleSetReplace: Encodable { let expectedRevision: Int; let rules: [KokoroCustomRuleInput] }

    public static func customRules() async throws -> KokoroCustomRulesState {
        try await decodeAuthorized(KokoroCustomRulesState.self, request: customRulesStateRequest())
    }

    public static func customRulesOptions() async throws -> KokoroCustomRulesOptions {
        try await decodeAuthorized(KokoroCustomRulesOptions.self, request: customRulesOptionsRequest())
    }

    public static func replaceRules(
        setID: Int,
        expectedRevision: Int,
        rules: [KokoroCustomRuleInput]
    ) async throws -> KokoroRuleSet {
        try await decodeAuthorized(
            KokoroRuleSet.self,
            request: try replaceRulesRequest(setID: setID, expectedRevision: expectedRevision, rules: rules)
        )
    }

    static func customRulesStateRequest() -> URLRequest {
        request(path: "app/custom-rules")
    }

    static func customRulesOptionsRequest() -> URLRequest {
        request(path: "app/custom-rules/options")
    }

    static func replaceRulesRequest(
        setID: Int,
        expectedRevision: Int,
        rules: [KokoroCustomRuleInput]
    ) throws -> URLRequest {
        try jsonRequest(
            path: "app/custom-rules/sets/\(setID)/rules",
            method: "PUT",
            body: RuleSetReplace(expectedRevision: expectedRevision, rules: rules)
        )
    }

    private static func jsonRequest<Body: Encodable>(path: String, method: String, body: Body) throws -> URLRequest {
        var result = request(path: path, method: method)
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.httpBody = try encoder.encode(body)
        return result
    }
}
