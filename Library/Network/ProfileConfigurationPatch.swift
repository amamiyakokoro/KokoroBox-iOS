import Foundation

/// Runtime-only additions to the selected sing-box configuration.
///
/// The stored profile is deliberately left untouched. Rebuilding the patch for each
/// service start prevents rules from being duplicated across reloads or updates.
public enum ProfileConfigurationPatch {
    public static func applying(
        to configuration: String,
        blockChinaICloudMail: Bool,
        blockQUIC: Bool
    ) throws -> String {
        guard blockChinaICloudMail || blockQUIC else { return configuration }
        guard let data = configuration.data(using: .utf8),
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ProfileConfigurationPatchError.invalidConfiguration
        }

        var route = root["route"] as? [String: Any] ?? [:]
        var rules = route["rules"] as? [[String: Any]] ?? []
        var ruleSets = route["rule_set"] as? [[String: Any]] ?? []
        var additions: [[String: Any]] = []
        var didChange = false
        var didChangeRuleSets = false

        if blockChinaICloudMail {
            if !ruleSets.contains(where: isChinaICloudMailRuleSet) {
                ruleSets.append([
                    "tag": "geoip-cn",
                    "type": "remote",
                    "format": "binary",
                    "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
                ])
                didChange = true
                didChangeRuleSets = true
            }
            if !rules.contains(where: isChinaICloudMailRule) {
                additions.append([
                    "port": 993,
                    "rule_set": "geoip-cn",
                    "action": "reject",
                ])
            }
        }
        if blockQUIC, !rules.contains(where: isQUICBlockRule) {
            additions.append([
                "network": "udp",
                "port": 443,
                "action": "reject",
            ])
        }

        if !additions.isEmpty {
            let insertionIndex = rules.firstIndex(where: { ($0["action"] as? String) == "sniff" }) ?? rules.endIndex
            rules.insert(contentsOf: additions, at: insertionIndex)
            route["rules"] = rules
            didChange = true
        }

        guard didChange else { return configuration }
        if didChangeRuleSets {
            route["rule_set"] = ruleSets
        }
        root["route"] = route

        let patchedData = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        guard let patchedConfiguration = String(data: patchedData, encoding: .utf8) else {
            throw ProfileConfigurationPatchError.invalidConfiguration
        }
        return patchedConfiguration
    }

    private static func isChinaICloudMailRule(_ rule: [String: Any]) -> Bool {
        numberValue(rule["port"]) == 993
            && (rule["rule_set"] as? String) == "geoip-cn"
            && (rule["action"] as? String) == "reject"
    }

    private static func isChinaICloudMailRuleSet(_ ruleSet: [String: Any]) -> Bool {
        (ruleSet["tag"] as? String) == "geoip-cn"
    }

    private static func isQUICBlockRule(_ rule: [String: Any]) -> Bool {
        (rule["network"] as? String) == "udp"
            && numberValue(rule["port"]) == 443
            && (rule["action"] as? String) == "reject"
    }

    private static func numberValue(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }
}

private enum ProfileConfigurationPatchError: LocalizedError {
    case invalidConfiguration

    var errorDescription: String? {
        String(localized: "The selected profile is not a valid JSON configuration.")
    }
}
