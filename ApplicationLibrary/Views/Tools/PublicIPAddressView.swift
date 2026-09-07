import Foundation
import Network
import SwiftUI

@MainActor
public struct PublicIPAddressView: View {
    @StateObject private var viewModel = PublicIPAddressViewModel()

    public init() {}

    public var body: some View {
        FormView {
            Section("Network") {
                FormTextItem("Public IP", "globe") {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Text(verbatim: viewModel.address ?? "-")
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
        .navigationTitle("IP Address")
        .task {
            await viewModel.refresh()
        }
        .alert($viewModel.alert)
    }
}

@MainActor
private final class PublicIPAddressViewModel: BaseViewModel {
    @Published private(set) var address: String?

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            address = try await Self.fetchAddress()
        } catch is CancellationError {
            return
        } catch {
            alert = AlertState(errorMessage: String(localized: "Could not retrieve the public IP address."))
        }
    }

    private nonisolated static func fetchAddress() async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.ip.sb/ip")!)
        request.timeoutInterval = 15
        request.setValue("text/plain", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200 ..< 300).contains(response.statusCode),
              let text = String(data: data, encoding: .utf8)
        else {
            throw PublicIPAddressError.invalidResponse
        }

        let address = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.utf8.count <= 45,
              IPv4Address(address) != nil || IPv6Address(address) != nil
        else {
            throw PublicIPAddressError.invalidResponse
        }
        return address
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }()
}

private enum PublicIPAddressError: Error {
    case invalidResponse
}
