#if !os(tvOS)
    import Library
    import SwiftUI

    @MainActor
    public struct KokoroSubscriptionView: View {
        @EnvironmentObject private var environments: ExtensionEnvironments
        @Environment(\.dismiss) private var dismiss
        @StateObject private var viewModel = KokoroSubscriptionViewModel()

        private let onSuccess: ((Profile) async -> Void)?

        public init(onSuccess: ((Profile) async -> Void)? = nil) {
            self.onSuccess = onSuccess
        }

        public var body: some View {
            #if os(macOS)
                macOSBody
            #else
                iOSBody
            #endif
        }

        private var formContent: some View {
            FormView {
                if !viewModel.isSignedIn {
                    Section {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            FormButton {
                                Task { await viewModel.signIn() }
                            } label: {
                                Label("Sign in with Kokoro", systemImage: "person.crop.circle.badge.checkmark")
                            }
                        }
                    } header: {
                        Text("Kokoro Subscription")
                    } footer: {
                        Text("Sign in securely with osu! in your system browser. This app never receives your osu! password.")
                    }
                } else {
                    accountSection
                    subscriptionSection
                    routeSection
                    updateSection

                    #if os(iOS)
                        Section {
                            createButton
                        }
                    #endif

                    Section {
                        FormButton(role: .destructive) {
                            Task { await viewModel.signOut() }
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }
            }
        }

        @ViewBuilder
        private var accountSection: some View {
            if let user = viewModel.user {
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
        }

        @ViewBuilder
        private var subscriptionSection: some View {
            if let options = viewModel.options {
                Section {
                    FormPicker(
                        String(localized: "Protocol"),
                        options: viewModel.protocolOptions.map { FormPickerOption($0.value, $0.label) },
                        selection: Binding(
                            get: { viewModel.selectedProtocol },
                            set: { viewModel.selectProtocol($0) }
                        )
                    )
                    FormPicker(
                        String(localized: "Plan"),
                        options: viewModel.planOptions.map { FormPickerOption($0.name, $0.name) },
                        selection: Binding(
                            get: { viewModel.selectedPlan },
                            set: { viewModel.selectPlan($0) }
                        )
                    )
                    FormPicker(
                        String(localized: "ISP"),
                        options: viewModel.ispOptions.map { FormPickerOption($0.value, $0.label) },
                        selection: $viewModel.selectedISP
                    )
                    if viewModel.supportsDirectMode {
                        FormPicker(
                            String(localized: "Mode"),
                            options: [
                                FormPickerOption("relay", String(localized: "Relay")),
                                FormPickerOption("direct", String(localized: "Direct")),
                            ],
                            selection: $viewModel.selectedMode
                        )
                    }
                } header: {
                    Text("Subscription")
                } footer: {
                    if options.formats.first(where: { $0.value == "sing-box" })?.testing == true {
                        Text("Kokoro's sing-box 1.14 renderer is currently in testing.")
                    }
                }
            }
        }

        @ViewBuilder
        private var routeSection: some View {
            if let options = viewModel.options {
                Section("Routing") {
                    FormPicker(
                        String(localized: "Rule Source"),
                        options: options.ruleSources.map { FormPickerOption($0, $0.capitalized) },
                        selection: $viewModel.selectedRuleSource
                    )
                    FormPicker(
                        String(localized: "Final Route"),
                        options: options.finalRoutes.map { FormPickerOption($0, $0.capitalized) },
                        selection: $viewModel.selectedFinalRoute
                    )
                }
            }
        }

        @ViewBuilder
        private var updateSection: some View {
            if viewModel.options != nil {
                Section("Updates") {
                    Toggle("Update Rule Providers", isOn: $viewModel.ruleProviderAutoUpdate)
                    Toggle("Update Profile Automatically", isOn: $viewModel.profileAutoUpdate)
                    FormItem(String(localized: "Profile Update Interval")) {
                        Stepper(value: $viewModel.profileUpdateHours, in: viewModel.profileUpdateRange) {
                            Text("\(viewModel.profileUpdateHours) hours")
                                .monospacedDigit()
                        }
                    }
                }
            }
        }

        private var createButton: some View {
            Group {
                if viewModel.isSaving {
                    ProgressView()
                } else {
                    FormButton {
                        Task { await createProfile() }
                    } label: {
                        Label("Create Subscription", systemImage: "cloud.badge.plus")
                    }
                }
            }
        }

        #if os(macOS)
            private var macOSBody: some View {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Kokoro Subscription")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 12)
                    formContent
                }
                .frame(minWidth: 520, minHeight: 560)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if viewModel.isSaving {
                            ProgressView()
                        } else {
                            Button("Create") {
                                Task { await createProfile() }
                            }
                            .disabled(!viewModel.isSignedIn || viewModel.options == nil)
                        }
                    }
                }
                .disabled(viewModel.isSaving)
                .alert($viewModel.alert)
                .task { await viewModel.loadIfNeeded() }
            }
        #else
            private var iOSBody: some View {
                formContent
                    .navigationTitle("Kokoro Subscription")
                    .navigationBarTitleDisplayMode(.inline)
                    .disabled(viewModel.isSaving)
                    .alert($viewModel.alert)
                    .task { await viewModel.loadIfNeeded() }
            }
        #endif

        private func createProfile() async {
            guard let profile = await viewModel.createProfile(environments: environments) else { return }
            if let onSuccess {
                await onSuccess(profile)
            }
            dismiss()
        }

        private static func byteCount(_ count: Int64) -> String {
            ByteCountFormatter.string(fromByteCount: count, countStyle: .binary)
        }
    }
#endif
