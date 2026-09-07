import Foundation
import SwiftUI

#if canImport(Darwin)
    import Darwin
#endif
#if os(iOS)
    import CoreLocation
    import NetworkExtension
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
private final class NetworkInterfacesDiagnosticsViewModel: BaseViewModel {
    @Published private(set) var wifi = WiFiDetails.unavailable
    @Published private(set) var interfaces: [NetworkInterfaceDetails] = []
    #if os(iOS)
        private let wifiAuthorization = WiFiAuthorizationRequester()
    #endif

    override init() {
        super.init()
        #if os(iOS)
            wifiAuthorization.onAuthorizationChanged = { [weak self] in
                Task { await self?.refresh() }
            }
        #endif
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        #if os(iOS)
            wifiAuthorization.requestWhenInUseAuthorizationIfNeeded()
        #endif
        interfaces = DiagnosticsReader.networkInterfaces()
        wifi = await DiagnosticsReader.wifiDetails()
    }
}

@MainActor
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

#if os(iOS)
    @MainActor
    private final class WiFiAuthorizationRequester: NSObject, CLLocationManagerDelegate {
        private let locationManager = CLLocationManager()
        var onAuthorizationChanged: (() -> Void)?

        override init() {
            super.init()
            locationManager.delegate = self
        }

        func requestWhenInUseAuthorizationIfNeeded() {
            guard locationManager.authorizationStatus == .notDetermined else { return }
            locationManager.requestWhenInUseAuthorization()
        }

        nonisolated func locationManagerDidChangeAuthorization(_: CLLocationManager) {
            Task { @MainActor in
                self.onAuthorizationChanged?()
            }
        }
    }
#endif
