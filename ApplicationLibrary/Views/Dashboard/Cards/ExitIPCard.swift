import Library
import SwiftUI

@MainActor
public struct ExitIPCard: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = PublicIPAddressViewModel()

    public init() {}

    public var body: some View {
        DashboardCardView(title: "") {
            VStack(alignment: .leading, spacing: 12) {
                DashboardCardHeader(icon: "globe.asia.australia.fill", title: "Exit IP")
                content
            }
        }
        .task {
            guard !Variant.screenshotMode else { return }
            await refreshLoop()
        }
        .onChangeCompat(of: scenePhase) { phase in
            guard !Variant.screenshotMode, phase == .active else { return }
            Task { await viewModel.refresh(reportErrors: false) }
        }
    }

    @ViewBuilder
    private var content: some View {
        let info = Variant.screenshotMode
            ? PublicIPInfo(address: "203.0.113.1", countryCode: "TW")
            : viewModel.info

        HStack(spacing: 12) {
            if let countryCode = info?.countryCode {
                CountryFlagImage(countryCode: countryCode, size: 32)
            } else {
                Image(systemName: "globe")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: info?.address ?? "--")
                    .font(.subheadline.monospaced())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let countryCode = info?.countryCode {
                    Text(verbatim: countryCode)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if viewModel.isLoading, viewModel.info == nil, !Variant.screenshotMode {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func refreshLoop() async {
        await viewModel.refresh(reportErrors: false)
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            } catch {
                return
            }
            guard scenePhase == .active else { continue }
            await viewModel.refresh(reportErrors: false)
        }
    }
}
