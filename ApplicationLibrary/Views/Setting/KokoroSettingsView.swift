#if !os(tvOS)
    import Library
    import SwiftUI

    @MainActor
    public struct KokoroSettingsView: View {
        @Environment(\.dismiss) private var dismiss
        @StateObject private var viewModel = KokoroSettingsViewModel()

        public init() {}

        public var body: some View {
            Group {
                if viewModel.isLoading, !viewModel.isSignedIn {
                    ProgressView()
                } else if !viewModel.isSignedIn {
                    signedOutContent
                } else if let user = viewModel.user {
                    signedInContent(user)
                } else if viewModel.isLoading {
                    ProgressView()
                } else {
                    unavailableContent
                }
            }
            .navigationTitle("Kokoro Settings")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #elseif os(macOS)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await viewModel.reload() }
                        } label: {
                            Label("Reload", systemImage: "arrow.clockwise")
                        }
                        .disabled(viewModel.isLoading || !viewModel.isSignedIn)
                    }
                }
            #endif
            .task { await viewModel.loadIfNeeded() }
            .onDisappear { viewModel.cancelSignIn() }
            .refreshable {
                if viewModel.isSignedIn { await viewModel.reload() }
            }
            .alert($viewModel.alert)
        }

        private var signedOutContent: some View {
            FormView {
                Section {
                    FormButton {
                        Task { await viewModel.signIn() }
                    } label: {
                        Label("Sign in with Kokoro", systemImage: "person.crop.circle.badge.checkmark")
                    }
                } header: {
                    Text("Kokoro Account")
                } footer: {
                    Text("Sign in securely with osu! in your system browser. This app never receives your osu! password.")
                }
            }
        }

        private func signedInContent(_ user: KokoroUser) -> some View {
            FormView {
                accountSection(user)

                Section {
                    FormNavigationLink {
                        KokoroCustomRulesView()
                    } label: {
                        Label("Custom Rules", systemImage: "list.bullet.rectangle")
                    }
                } header: {
                    Text("Routing")
                } footer: {
                    Text("Custom Rules override the default routing behavior in generated Kokoro configurations.")
                }

                Section {
                    FormButton(role: .destructive) {
                        Task { await viewModel.signOut() }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
        }

        private func accountSection(_ user: KokoroUser) -> some View {
            Section("Account") {
                HStack(spacing: 12) {
                    if let avatar = user.avatarUrl.flatMap(URL.init(string:)) {
                        AsyncImage(url: avatar) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: user.username ?? "osu! \(user.osuId)")
                            .font(.headline)
                        Text(verbatim: user.plans.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                FormTextItem("Traffic Used", Self.byteCount(user.trafficUsage))
                FormTextItem(
                    "Bandwidth Limit",
                    user.bandwidthLimit == 0 ? String(localized: "Unlimited") : Self.byteCount(user.bandwidthLimit)
                )
                if let expiration = user.subscriptionExpiresAt {
                    FormTextItem("Expires", expiration.replacingOccurrences(of: "T", with: " "))
                }
            }
        }

        private var unavailableContent: some View {
            FormView {
                Section {
                    Text("Kokoro account information is unavailable.")
                        .foregroundStyle(.secondary)
                    FormButton {
                        Task { await viewModel.reload() }
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                }
            }
        }

        private static func byteCount(_ count: Int64) -> String {
            ByteCountFormatter.string(fromByteCount: count, countStyle: .binary)
        }
    }
#endif
