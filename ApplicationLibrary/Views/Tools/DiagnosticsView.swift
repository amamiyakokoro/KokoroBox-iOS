import CFNetwork
import Foundation
import SwiftUI

#if canImport(Darwin)
    import Darwin
#endif
#if os(iOS)
    import NetworkExtension
#endif
#if os(macOS)
    import SystemConfiguration
#endif

@MainActor
public struct DiagnosticsView: View {
    public init() {}

    public var body: some View {
        FormView {
            Section("Network Information") {
                FormNavigationLink {
                    NetworkInterfacesDiagnosticsView()
                } label: {
                    Label("Network Interfaces", systemImage: "wifi")
                }
                FormNavigationLink {
                    ProxyDNSDiagnosticsView()
                } label: {
                    Label("Proxy & DNS", systemImage: "network.badge.shield.half.filled")
                }
            }
        }
        .navigationTitle("Diagnostics")
    }
}

@MainActor
private struct NetworkInterfacesDiagnosticsView: View {
    @StateObject private var viewModel = NetworkInterfacesDiagnosticsViewModel()

    var body: some View {
        FormView {
            Section("Wi-Fi") {
                FormTextItem("SSID", viewModel.wifi.ssid)
                FormTextItem("BSSID", viewModel.wifi.bssid)
            }

            Section("Network Interfaces") {
                if viewModel.interfaces.isEmpty, !viewModel.isLoading {
                    Text("No active network interfaces.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.interfaces) { interface in
                        diagnosticItem(interface.name, interface.detail)
                    }
                }
            }

            Section("Action") {
                FormButton {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .navigationTitle("Network Interfaces")
        .task {
            await viewModel.refresh()
        }
    }
}

@MainActor
private struct ProxyDNSDiagnosticsView: View {
    @StateObject private var viewModel = ProxyDNSDiagnosticsViewModel()

    var body: some View {
        FormView {
            Section("Proxy Settings") {
                FormTextItem("HTTP", viewModel.proxy.http)
                FormTextItem("HTTPS", viewModel.proxy.https)
                FormTextItem("PAC", viewModel.proxy.pac)
            }

            Section("DNS Servers") {
                if viewModel.dnsServers.isEmpty {
                    Text("System DNS information is unavailable to sandboxed apps.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.dnsServers, id: \.self) { server in
                        Text(verbatim: server)
                    }
                }
            }

            Section("Action") {
                FormButton {
                    viewModel.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .navigationTitle("Proxy & DNS")
        .onAppear {
            viewModel.refresh()
        }
    }
}

@MainActor
private final class NetworkInterfacesDiagnosticsViewModel: BaseViewModel {
    @Published private(set) var wifi = WiFiDetails.unavailable
    @Published private(set) var interfaces: [NetworkInterfaceDetails] = []

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        interfaces = DiagnosticsReader.networkInterfaces()
        wifi = await DiagnosticsReader.wifiDetails()
    }
}

@MainActor
private final class ProxyDNSDiagnosticsViewModel: ObservableObject {
    @Published private(set) var proxy = ProxyDetails.unavailable
    @Published private(set) var dnsServers: [String] = []

    func refresh() {
        proxy = DiagnosticsReader.proxyDetails()
        dnsServers = DiagnosticsReader.dnsServers()
    }
}

private struct WiFiDetails {
    let ssid: String
    let bssid: String

    static let unavailable = WiFiDetails(
        ssid: String(localized: "Unavailable"),
        bssid: String(localized: "Unavailable")
    )
}

private struct NetworkInterfaceDetails: Identifiable {
    let name: String
    let addresses: [String]
    let mtu: Int?

    var id: String { name }

    var detail: String {
        let addressText = addresses.joined(separator: ", ")
        guard let mtu else { return addressText }
        return "IP: \(addressText), MTU: \(mtu)"
    }
}

private struct ProxyDetails {
    let http: String
    let https: String
    let pac: String

    static let unavailable = ProxyDetails(
        http: String(localized: "Unavailable"),
        https: String(localized: "Unavailable"),
        pac: String(localized: "Unavailable")
    )
}

@ViewBuilder
private func diagnosticItem(_ name: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
        Text(verbatim: name)
        Text(verbatim: value)
            .multilineTextAlignment(.trailing)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private enum DiagnosticsReader {
    static func wifiDetails() async -> WiFiDetails {
        #if os(iOS)
            guard #available(iOS 14.0, *), let network = await NEHotspotNetwork.fetchCurrent() else {
                return .unavailable
            }
            return WiFiDetails(
                ssid: network.ssid.isEmpty ? String(localized: "Unavailable") : network.ssid,
                bssid: network.bssid.isEmpty ? String(localized: "Unavailable") : network.bssid
            )
        #else
            return .unavailable
        #endif
    }

    static func networkInterfaces() -> [NetworkInterfaceDetails] {
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0, let firstAddress else { return [] }
        defer { freeifaddrs(firstAddress) }

        var addresses: [String: Set<String>] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let current = cursor {
            let interface = current.pointee
            cursor = interface.ifa_next

            guard interface.ifa_flags & UInt32(IFF_UP) != 0,
                  let address = interface.ifa_addr,
                  let addressText = numericAddress(address)
            else { continue }

            let name = String(cString: interface.ifa_name)
            addresses[name, default: []].insert(addressText)
        }

        return addresses.map { name, addresses in
            NetworkInterfaceDetails(
                name: name,
                addresses: addresses.sorted(),
                mtu: nil
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func proxyDetails() -> ProxyDetails {
        guard let settings = CFNetworkCopySystemProxySettings() as? [String: Any] else {
            return .unavailable
        }

        return ProxyDetails(
            http: proxyDescription(settings, enable: "HTTPEnable", host: "HTTPProxy", port: "HTTPPort"),
            https: proxyDescription(settings, enable: "HTTPSEnable", host: "HTTPSProxy", port: "HTTPSPort"),
            pac: automaticProxyDescription(settings)
        )
    }

    static func dnsServers() -> [String] {
        #if os(macOS)
            guard let store = SCDynamicStoreCreate(nil, "KokoroBox.Diagnostics" as CFString, nil, nil),
                  let settings = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any]
            else { return [] }
            return settings["ServerAddresses"] as? [String] ?? []
        #else
            return []
        #endif
    }

    private static func proxyDescription(_ settings: [String: Any], enable: String, host: String, port: String) -> String {
        guard (settings[enable] as? NSNumber)?.boolValue == true else { return String(localized: "Disabled") }
        guard let host = settings[host] as? String, !host.isEmpty else { return String(localized: "Enabled") }
        guard let port = settings[port] as? NSNumber else { return host }
        return "\(host):\(port.intValue)"
    }

    private static func automaticProxyDescription(_ settings: [String: Any]) -> String {
        guard (settings["ProxyAutoConfigEnable"] as? NSNumber)?.boolValue == true else { return String(localized: "Disabled") }
        return settings["ProxyAutoConfigURLString"] as? String ?? String(localized: "Enabled")
    }

    private static func numericAddress(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        let family = Int32(address.pointee.sa_family)
        guard family == AF_INET || family == AF_INET6 else { return nil }

        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            address,
            socklen_t(address.pointee.sa_len),
            &host,
            socklen_t(host.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard result == 0 else { return nil }
        return String(cString: host)
    }

}
