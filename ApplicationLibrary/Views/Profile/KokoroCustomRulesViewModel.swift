#if !os(tvOS)
    import Foundation
    import Library

    struct KokoroCustomRuleDraft: Identifiable, Hashable {
        let id: UUID
        var type: String
        var payload: String
        var target: String

        init(id: UUID = UUID(), type: String, payload: String?, target: String) {
            self.id = id
            self.type = type
            self.payload = payload ?? ""
            self.target = target
        }

        init(_ rule: KokoroCustomRule) {
            self.init(type: rule.type, payload: rule.payload, target: rule.target)
        }

        var input: KokoroCustomRuleInput {
            KokoroCustomRuleInput(type: type, payload: type == "MATCH" ? nil : payload, target: target)
        }
    }

    private enum KokoroCustomRulesClientError: LocalizedError {
        case defaultRuleSetUnavailable

        var errorDescription: String? {
            String(localized: "The default rule set is unavailable.")
        }
    }

    @MainActor
    final class KokoroCustomRulesViewModel: BaseViewModel {
        @Published private(set) var isSignedIn = false
        @Published private(set) var ruleSet: KokoroRuleSet?
        @Published private(set) var options: KokoroCustomRulesOptions?
        @Published var rules: [KokoroCustomRuleDraft] = []
        @Published var isSaving = false
        @Published var showConflictResolution = false
        @Published private(set) var remoteConflict: KokoroRuleSet?

        private let authenticator = KokoroWebAuthenticator.shared
        private let preloadStore = KokoroPreloadStore.shared
        private var signInTask: Task<Void, Error>?
        private var didLoad = false

        var validationMessage: String? {
            guard let options else { return nil }
            do {
                try KokoroCustomRulesValidator.validate(rules.map(\.input), options: options)
                return nil
            } catch {
                return error.localizedDescription
            }
        }

        var canAddRule: Bool {
            guard let options else { return false }
            return rules.count < options.maximumRulesPerSet
        }

        func loadIfNeeded() async {
            guard !didLoad else { return }
            didLoad = true
            guard await KokoroSession.shared.hasSession() else { return }
            await loadRules(forceRefresh: false)
        }

        func reload() async {
            await loadRules(forceRefresh: true)
        }

        private func loadRules(forceRefresh: Bool) async {
            isLoading = true
            defer { isLoading = false }
            do {
                try await fetchDefaultRuleSetAndOptions(forceRefresh: forceRefresh)
                isSignedIn = true
            } catch {
                isSignedIn = await KokoroSession.shared.hasSession()
                alert = AlertState(action: String(localized: "load custom rules"), error: error)
            }
        }

        func signIn() async {
            guard signInTask == nil else { return }
            isLoading = true
            defer { isLoading = false; signInTask = nil }
            do {
                let task = Task { try await authenticator.signIn() }
                signInTask = task
                try await task.value
                isSignedIn = true
                await preloadStore.invalidateAll()
                try await fetchDefaultRuleSetAndOptions(forceRefresh: true)
            } catch is CancellationError {
                return
            } catch {
                isSignedIn = await KokoroSession.shared.hasSession()
                if isSignedIn {
                    alert = AlertState(action: String(localized: "load custom rules"), error: error)
                } else {
                    alert = AlertState(
                        errorMessage: "\(String(localized: "Failed to sign in to Kokoro"))\n\(error.localizedDescription)"
                    )
                }
            }
        }

        func cancelSignIn() {
            signInTask?.cancel()
        }

        func refreshOptions() async throws {
            options = try await preloadStore.customRuleOptions(forceRefresh: true)
        }

        func save() async {
            guard let ruleSet, !isSaving else { return }
            isSaving = true
            defer { isSaving = false }
            let targetRules = rules.map(\.input)
            do {
                try await refreshOptions()
                guard let options else { throw KokoroCustomRulesClientError.defaultRuleSetUnavailable }
                try KokoroCustomRulesValidator.validate(targetRules, options: options)
                let updated = try await KokoroAPI.replaceRules(
                    setID: ruleSet.id,
                    expectedRevision: ruleSet.revision,
                    rules: targetRules
                )
                await preloadStore.invalidateCustomRuleState()
                apply(updated)
            } catch KokoroAPIError.networkTimeout {
                await reconcileUnknownSave(targetRules)
            } catch KokoroAPIError.conflict {
                await prepareConflict()
            } catch let KokoroAPIError.http(status, _) where status == 404 {
                self.ruleSet = nil
                rules = []
                alert = AlertState(errorMessage: String(localized: "The default rule set is unavailable."))
            } catch let KokoroAPIError.http(status, detail) where status == 422 {
                try? await refreshOptions()
                alert = AlertState(
                    action: String(localized: "save custom rules"),
                    error: KokoroAPIError.http(status: status, detail: detail)
                )
            } catch {
                alert = AlertState(action: String(localized: "save custom rules"), error: error)
            }
        }

        func reapplyLocalChanges() {
            guard let remoteConflict else { return }
            ruleSet = remoteConflict
            clearConflict()
        }

        func mergeChanges() {
            guard let remoteConflict else { return }
            let local = rules.map(\.input)
            var merged = remoteConflict.rules.map(\.input).filter { $0.type != "MATCH" }
            for rule in local where rule.type != "MATCH" && !merged.contains(rule) {
                merged.append(rule)
            }
            if let match = local.last(where: { $0.type == "MATCH" })
                ?? remoteConflict.rules.map(\.input).last(where: { $0.type == "MATCH" }) {
                merged.append(match)
            }
            guard let options, merged.count <= options.maximumRulesPerSet else {
                alert = AlertState(errorMessage: KokoroCustomRulesValidationError.tooManyRules.localizedDescription)
                return
            }
            ruleSet = remoteConflict
            rules = merged.map { KokoroCustomRuleDraft(type: $0.type, payload: $0.payload, target: $0.target) }
            clearConflict()
        }

        func discardLocalChanges() {
            guard let remoteConflict else { return }
            apply(remoteConflict)
            clearConflict()
        }

        private func reconcileUnknownSave(_ targetRules: [KokoroCustomRuleInput]) async {
            do {
                let remote = try await currentRemoteSet()
                if remote.hasSameRules(as: targetRules) {
                    apply(remote)
                } else {
                    remoteConflict = remote
                    showConflictResolution = true
                }
            } catch {
                alert = AlertState(action: String(localized: "check saved custom rules"), error: error)
            }
        }

        private func prepareConflict() async {
            do {
                remoteConflict = try await currentRemoteSet()
                showConflictResolution = true
            } catch {
                alert = AlertState(action: String(localized: "reload changed custom rules"), error: error)
            }
        }

        private func currentRemoteSet() async throws -> KokoroRuleSet {
            let state = try await preloadStore.customRules(forceRefresh: true)
            guard let remote = state.defaultRuleSet else {
                throw KokoroCustomRulesClientError.defaultRuleSetUnavailable
            }
            return remote
        }

        private func apply(_ updated: KokoroRuleSet) {
            ruleSet = updated
            rules = updated.rules.map(KokoroCustomRuleDraft.init)
        }

        private func fetchDefaultRuleSetAndOptions(forceRefresh: Bool) async throws {
            async let state = preloadStore.customRules(forceRefresh: forceRefresh)
            async let options = preloadStore.customRuleOptions(forceRefresh: forceRefresh)
            let (loadedState, loadedOptions) = try await (state, options)
            self.options = loadedOptions
            guard let defaultRuleSet = loadedState.defaultRuleSet else {
                ruleSet = nil
                rules = []
                throw KokoroCustomRulesClientError.defaultRuleSetUnavailable
            }
            apply(defaultRuleSet)
        }

        private func clearConflict() {
            remoteConflict = nil
            showConflictResolution = false
        }
    }
#endif
