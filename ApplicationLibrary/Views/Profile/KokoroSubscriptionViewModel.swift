#if !os(tvOS)
    import Foundation
    import Libbox
    import Library

    @MainActor
    final class KokoroSubscriptionViewModel: BaseViewModel {
        @Published var isSignedIn = false
        @Published var isSaving = false
        @Published var user: KokoroUser?
        @Published var options: KokoroSubscriptionOptions?

        @Published var selectedProtocol = ""
        @Published var selectedPlan = ""
        @Published var selectedISP = ""
        @Published var selectedMode = "relay"
        @Published var selectedRuleSource = "origin"
        @Published var selectedFinalRoute = "proxy"
        @Published var ruleProviderAutoUpdate = true
        @Published var profileAutoUpdate = true
        @Published var profileUpdateHours = 1

        private let authenticator = KokoroWebAuthenticator.shared
        private var signInTask: Task<Void, Error>?
        private var didLoad = false

        var protocolOptions: [KokoroProtocolOption] {
            let supportedProtocols = Set(["vmess", "anytls", "hysteria2"])
            return options?.protocols.filter { supportedProtocols.contains($0.value) } ?? []
        }

        var planOptions: [KokoroPlan] {
            options?.plans ?? []
        }

        var ispOptions: [KokoroISPOption] {
            guard let options else { return [] }
            guard let plan = options.plans.first(where: { $0.name == selectedPlan }) else {
                return options.isps.filter { $0.value.isEmpty }
            }
            let supported = Set(plan.supportedIsps)
            if supported.isEmpty || supported == ["all"] {
                return options.isps.filter { $0.value.isEmpty }
            }
            return options.isps.filter { $0.value.isEmpty || supported.contains($0.value) }
        }

        var supportsDirectMode: Bool {
            selectedProtocol != "vmess"
                && protocolOptions.first(where: { $0.value == selectedProtocol })?.supportsDirect == true
        }

        var profileUpdateRange: ClosedRange<Int> {
            guard let range = options?.profileUpdate else { return 1 ... 720 }
            return max(range.minHours, 1) ... max(range.maxHours, max(range.minHours, 1))
        }

        func loadIfNeeded() async {
            guard !didLoad else { return }
            didLoad = true
            guard await KokoroSession.shared.hasSession() else { return }
            await loadAccount()
        }

        func signIn() async {
            guard signInTask == nil else { return }
            isLoading = true
            defer { isLoading = false; signInTask = nil }
            do {
                let task = Task { try await authenticator.signIn() }
                signInTask = task
                try await task.value
                try await fetchAccountAndOptions()
            } catch is CancellationError {
                return
            } catch {
                alert = AlertState(
                    errorMessage: "\(String(localized: "Failed to sign in to Kokoro"))\n\(error.localizedDescription)"
                )
            }
        }

        func cancelSignIn() { signInTask?.cancel() }

        func signOut() async {
            isLoading = true
            await KokoroSession.shared.revoke()
            user = nil
            options = nil
            isSignedIn = false
            selectedProtocol = ""
            selectedPlan = ""
            selectedISP = ""
            isLoading = false
        }

        func selectPlan(_ plan: String) {
            selectedPlan = plan
            if !ispOptions.contains(where: { $0.value == selectedISP }) {
                selectedISP = ""
            }
        }

        func selectProtocol(_ protocolValue: String) {
            selectedProtocol = protocolValue
            if !supportsDirectMode {
                selectedMode = "relay"
            }
        }

        func createProfile(environments: ExtensionEnvironments) async -> Profile? {
            isSaving = true
            defer { isSaving = false }
            do {
                guard isSignedIn, options != nil, !selectedProtocol.isEmpty else {
                    throw KokoroAPIError.noSession
                }
                let range = profileUpdateRange
                guard range.contains(profileUpdateHours) else {
                    throw KokoroAPIError.unsupportedConfiguration
                }

                let settings = KokoroResolveRequest(
                    protocol: selectedProtocol,
                    plan: selectedPlan.isEmpty ? nil : selectedPlan,
                    isp: selectedISP.isEmpty ? nil : selectedISP,
                    mode: supportsDirectMode ? selectedMode : "relay",
                    ruleSource: selectedRuleSource,
                    finalRoute: selectedFinalRoute,
                    ruleProviderAutoUpdate: ruleProviderAutoUpdate,
                    profileAutoUpdate: profileAutoUpdate,
                    profileUpdateHours: profileUpdateHours
                )
                let resolved = try await KokoroAPI.resolveSubscription(settings)
                guard resolved.format == "sing-box",
                      resolved.contentType.lowercased().hasPrefix("application/json"),
                      KokoroAPI.isAuthenticatedConfigurationURL(resolved.authenticatedConfigUrl)
                else {
                    throw KokoroAPIError.unsupportedConfiguration
                }

                let content = try await KokoroAPI.downloadConfiguration(from: resolved.authenticatedConfigUrl)
                try await BlockingIO.run {
                    var error: NSError?
                    LibboxCheckConfig(content, &error)
                    if let error {
                        throw error
                    }
                }

                let profile = try await persistProfile(
                    name: resolved.profileName,
                    remoteURL: resolved.authenticatedConfigUrl,
                    content: content
                )
                await SharedPreferences.selectedProfileID.set(profile.mustID)
                #if os(iOS)
                    try UIProfileUpdateTask.configure()
                #elseif os(macOS)
                    try await ProfileUpdateTask.configure()
                #endif
                environments.profileUpdate.send()
                return profile
            } catch {
                alert = AlertState(
                    errorMessage: "\(String(localized: "Failed to create Kokoro subscription"))\n\(error.localizedDescription)"
                )
                return nil
            }
        }

        private func loadAccount() async {
            isLoading = true
            defer { isLoading = false }
            do {
                try await fetchAccountAndOptions()
            } catch {
                isSignedIn = await KokoroSession.shared.hasSession()
                alert = AlertState(
                    errorMessage: "\(String(localized: "Failed to load Kokoro subscription"))\n\(error.localizedDescription)"
                )
            }
        }

        private func fetchAccountAndOptions() async throws {
            async let user = KokoroAPI.currentUser()
            async let options = KokoroAPI.subscriptionOptions()
            let (loadedUser, loadedOptions) = try await (user, options)
            guard loadedOptions.formats.contains(where: {
                $0.value == "sing-box" && ($0.targetVersion == nil || $0.targetVersion == "1.14")
            }) else {
                throw KokoroAPIError.unsupportedConfiguration
            }
            self.user = loadedUser
            self.options = loadedOptions
            isSignedIn = true
            applyDefaults(loadedOptions)
        }

        private func applyDefaults(_ options: KokoroSubscriptionOptions) {
            let protocols = protocolOptions
            if protocols.contains(where: { $0.value == options.defaults.protocol }) {
                selectedProtocol = options.defaults.protocol
            } else {
                selectedProtocol = protocols.first?.value ?? ""
            }

            if let defaultPlan = options.defaults.plan, options.plans.contains(where: { $0.name == defaultPlan }) {
                selectedPlan = defaultPlan
            } else {
                selectedPlan = options.plans.first?.name ?? ""
            }

            selectedISP = options.defaults.isp ?? ""
            if !ispOptions.contains(where: { $0.value == selectedISP }) {
                selectedISP = ""
            }
            selectedMode = supportsDirectMode ? options.defaults.mode : "relay"
            selectedRuleSource = options.ruleSources.contains(options.defaults.ruleSource)
                ? options.defaults.ruleSource
                : options.ruleSources.first ?? "origin"
            selectedFinalRoute = options.finalRoutes.contains(options.defaults.finalRoute)
                ? options.defaults.finalRoute
                : options.finalRoutes.first ?? "proxy"
            ruleProviderAutoUpdate = options.defaults.ruleProviderAutoUpdate
            profileAutoUpdate = options.defaults.profileAutoUpdate
            profileUpdateHours = min(max(options.defaults.profileUpdateHours, profileUpdateRange.lowerBound), profileUpdateRange.upperBound)
        }

        private nonisolated func persistProfile(name: String, remoteURL: String, content: String) async throws -> Profile {
            let nextProfileID = try await ProfileManager.nextID()
            let profileConfigDirectory = FilePath.sharedDirectory.appendingPathComponent("configs", isDirectory: true)
            let relativePath = "configs/config_\(nextProfileID).json"
            let profileConfig = FilePath.sharedDirectory.appendingPathComponent(relativePath)
            try await BlockingIO.run {
                try FileManager.default.createDirectory(at: profileConfigDirectory, withIntermediateDirectories: true)
                try content.write(to: profileConfig, atomically: true, encoding: .utf8)
            }

            do {
                let uniqueName = try await ProfileManager.uniqueName(name)
                let profile = Profile(
                    name: uniqueName,
                    type: .remote,
                    path: relativePath,
                    remoteURL: remoteURL,
                    autoUpdate: await profileAutoUpdate,
                    autoUpdateInterval: Int32(clamping: await profileUpdateHours * 60),
                    lastUpdated: .now
                )
                try await ProfileManager.create(profile)
                return profile
            } catch {
                try? await BlockingIO.run {
                    try FileManager.default.removeItem(at: profileConfig)
                }
                throw error
            }
        }
    }
#endif
