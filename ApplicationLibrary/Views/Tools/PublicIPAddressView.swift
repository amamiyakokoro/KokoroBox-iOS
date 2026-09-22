import Foundation
import Library
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
                    } else if let info = viewModel.info {
                        HStack(spacing: 8) {
                            if let countryCode = info.countryCode {
                                CountryFlagImage(countryCode: countryCode, size: 24)
                                Text(verbatim: countryCode)
                                    .fontWeight(.semibold)
                            }
                            Text(verbatim: info.address)
                                .font(.body.monospaced())
                        }
                    } else {
                        Text(verbatim: "-")
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
final class PublicIPAddressViewModel: BaseViewModel {
    @Published private(set) var info: PublicIPInfo?

    private let service: PublicIPInfoService

    init(service: PublicIPInfoService = PublicIPInfoService()) {
        self.service = service
        super.init()
    }

    func refresh(reportErrors: Bool = true) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            info = try await service.fetch()
        } catch is CancellationError {
            return
        } catch {
            if reportErrors {
                alert = AlertState(errorMessage: String(localized: "Could not retrieve the public IP address."))
            }
        }
    }
}
