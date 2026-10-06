import Foundation

/// Resolves registrable domains using the bundled ICANN and PRIVATE Public Suffix List.
enum KokoroDomainSuffix {
    private final class BundleMarker {}

    private struct Rules {
        var exact: Set<String> = []
        var wildcard: Set<String> = []
        var exceptions: Set<String> = []
    }

    private static let rules: Rules? = {
        #if SWIFT_PACKAGE
            let bundle = Bundle.module
        #else
            let bundle = Bundle(for: BundleMarker.self)
        #endif
        guard let url = bundle.url(forResource: "public_suffix_list", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var rules = Rules()
        for line in text.split(separator: "\n") {
            guard let entry = line.split(whereSeparator: \.isWhitespace).first,
                  !entry.hasPrefix("//") else { continue }
            if entry.hasPrefix("!") {
                if let name = canonicalHostname(String(entry.dropFirst())) { rules.exceptions.insert(name) }
            } else if entry.hasPrefix("*.") {
                if let name = canonicalHostname(String(entry.dropFirst(2))) { rules.wildcard.insert(name) }
            } else if let name = canonicalHostname(String(entry)) {
                rules.exact.insert(name)
            }
        }
        return rules
    }()

    static func registrableDomain(_ hostname: String) -> String? {
        guard let rules, let canonical = canonicalHostname(hostname) else { return nil }
        let labels = canonical.split(separator: ".")
        var suffixCount = 1 // PSL's default rule is *.
        for index in labels.indices {
            let suffix = labels[index...].joined(separator: ".")
            if rules.exceptions.contains(suffix) {
                return suffix // An exception removes its leftmost label from the public suffix.
            }
            if rules.exact.contains(suffix) {
                suffixCount = max(suffixCount, labels.count - index)
            }
            if index > 0, rules.wildcard.contains(suffix) {
                suffixCount = max(suffixCount, labels.count - index + 1)
            }
        }
        guard labels.count > suffixCount else { return nil }
        return labels.suffix(suffixCount + 1).joined(separator: ".")
    }

    private static func canonicalHostname(_ hostname: String) -> String? {
        guard !hostname.isEmpty,
              !hostname.contains(where: { $0.isWhitespace || "/:@%[]\\".contains($0) }),
              !hostname.split(separator: ".", omittingEmptySubsequences: false).contains(where: \.isEmpty),
              let host = URL(string: "https://" + hostname)?.host else { return nil }
        let canonical = host.lowercased()
        guard canonical.utf8.allSatisfy({ byte in
            (97 ... 122).contains(byte) || (48 ... 57).contains(byte) || byte == 45 || byte == 46
        }) else { return nil }
        return canonical
    }
}
