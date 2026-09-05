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

    @MainActor
    final class KokoroCustomRulesViewModel: BaseViewModel {
        @Published private(set) var isSignedIn = false
        @Published private(set) var sets: [KokoroRuleSet] = []
        @Published private(set) var options: KokoroCustomRulesOptions?
        private let authenticator = KokoroWebAuthenticator.shared
        private var signInTask: Task<Void, Error>?
        private var didLoad = false

        func loadIfNeeded() async {
            guard !didLoad else { return }
            didLoad = true
            guard await KokoroSession.shared.hasSession() else { return }
            await reload()
        }

        func reload() async {
            isLoading = true
            defer { isLoading = false }
            do {
                try await fetchStateAndOptions()
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
                try await fetchStateAndOptions()
                isSignedIn = true
            } catch is CancellationError {
                return
            } catch {
                isSignedIn = await KokoroSession.shared.hasSession()
                alert = AlertState(
                    errorMessage: "\(String(localized: "Failed to sign in to Kokoro"))\n\(error.localizedDescription)"
                )
            }
        }

        func cancelSignIn() {
            signInTask?.cancel()
        }

        func createSet(name: String) async -> Bool {
            isLoading = true
            defer { isLoading = false }
            do {
                async let state = KokoroAPI.customRules()
                async let options = KokoroAPI.customRulesOptions()
                let (currentState, currentOptions) = try await (state, options)
                sets = currentState.sets
                self.options = currentOptions
                try KokoroCustomRulesValidator.validateName(name, options: currentOptions)
                guard currentState.sets.count < currentOptions.maximumRuleSets else {
                    throw KokoroAPIError.conflict(currentRevision: nil)
                }
                let created = try await KokoroAPI.createRuleSet(name: name)
                sets.append(created)
                return true
            } catch {
                alert = AlertState(action: String(localized: "create rule set"), error: error)
                return false
            }
        }

        func update(_ set: KokoroRuleSet) {
            if let index = sets.firstIndex(where: { $0.id == set.id }) {
                sets[index] = set
            } else {
                sets.append(set)
            }
        }

        func remove(id: Int) {
            sets.removeAll { $0.id == id }
        }

        private func fetchStateAndOptions() async throws {
            async let state = KokoroAPI.customRules()
            async let options = KokoroAPI.customRulesOptions()
            let (loadedState, loadedOptions) = try await (state, options)
            sets = loadedState.sets
            self.options = loadedOptions
        }
    }

    @MainActor
    final class KokoroRuleSetViewModel: BaseViewModel {
        @Published private(set) var ruleSet: KokoroRuleSet
        @Published private(set) var options: KokoroCustomRulesOptions
        @Published var rules: [KokoroCustomRuleDraft]
        @Published var isSaving = false
        @Published var showConflictResolution = false
        @Published private(set) var remoteConflict: KokoroRuleSet?

        private let onUpdate: (KokoroRuleSet) -> Void
        private let onDelete: (Int) -> Void

        init(
            ruleSet: KokoroRuleSet,
            options: KokoroCustomRulesOptions,
            onUpdate: @escaping (KokoroRuleSet) -> Void,
            onDelete: @escaping (Int) -> Void
        ) {
            self.ruleSet = ruleSet
            self.options = options
            rules = ruleSet.rules.map(KokoroCustomRuleDraft.init)
            self.onUpdate = onUpdate
            self.onDelete = onDelete
        }

        var validationMessage: String? {
            do {
                try KokoroCustomRulesValidator.validate(rules.map(\.input), options: options)
                return nil
            } catch {
                return error.localizedDescription
            }
        }

        var canAddRule: Bool { rules.count < options.maximumRulesPerSet }

        func refreshOptions() async throws {
            options = try await KokoroAPI.customRulesOptions()
        }

        func save() async {
            guard !isSaving else { return }
            isSaving = true
            defer { isSaving = false }
            let targetRules = rules.map(\.input)
            do {
                try await refreshOptions()
                try KokoroCustomRulesValidator.validate(targetRules, options: options)
                let updated = try await KokoroAPI.replaceRules(
                    setID: ruleSet.id,
                    expectedRevision: ruleSet.revision,
                    rules: targetRules
                )
                apply(updated)
            } catch KokoroAPIError.networkTimeout {
                await reconcileUnknownSave(targetRules)
            } catch KokoroAPIError.conflict {
                await prepareConflict()
            } catch let KokoroAPIError.http(status, _) where status == 404 {
                onDelete(ruleSet.id)
                alert = AlertState(errorMessage: String(localized: "This rule set no longer exists."))
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

        func rename(to name: String) async -> Bool {
            guard !isSaving else { return false }
            isSaving = true
            defer { isSaving = false }
            do {
                try await refreshOptions()
                try KokoroCustomRulesValidator.validateName(name, options: options)
                let updated = try await KokoroAPI.renameRuleSet(
                    id: ruleSet.id,
                    name: name,
                    expectedRevision: ruleSet.revision
                )
                apply(updated)
                return true
            } catch KokoroAPIError.networkTimeout {
                if let remote = try? await currentRemoteSet(), remote.name == name {
                    apply(remote)
                    return true
                }
                alert = AlertState(errorMessage: String(localized: "The rename result is unknown. Reload before trying again."))
            } catch KokoroAPIError.conflict {
                if let remote = try? await currentRemoteSet() { apply(remote) }
                alert = AlertState(errorMessage: String(localized: "This rule set changed elsewhere. Its latest version has been loaded."))
            } catch {
                alert = AlertState(action: String(localized: "rename rule set"), error: error)
            }
            return false
        }

        func delete() async -> Bool {
            guard !ruleSet.isDefault, !isSaving else { return false }
            isSaving = true
            defer { isSaving = false }
            do {
                try await KokoroAPI.deleteRuleSet(id: ruleSet.id, expectedRevision: ruleSet.revision)
                onDelete(ruleSet.id)
                return true
            } catch KokoroAPIError.networkTimeout {
                do {
                    _ = try await currentRemoteSet()
                    alert = AlertState(errorMessage: String(localized: "The delete result is unknown. Reload before trying again."))
                } catch let KokoroAPIError.http(status, _) where status == 404 {
                    onDelete(ruleSet.id)
                    return true
                } catch {
                    alert = AlertState(action: String(localized: "check rule set"), error: error)
                }
            } catch KokoroAPIError.conflict {
                if let remote = try? await currentRemoteSet() { apply(remote) }
                alert = AlertState(errorMessage: String(localized: "This rule set changed elsewhere. Its latest version has been loaded."))
            } catch {
                alert = AlertState(action: String(localized: "delete rule set"), error: error)
            }
            return false
        }

        func reapplyLocalChanges() {
            guard let remoteConflict else { return }
            ruleSet = remoteConflict
            onUpdate(remoteConflict)
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
            guard merged.count <= options.maximumRulesPerSet else {
                alert = AlertState(errorMessage: KokoroCustomRulesValidationError.tooManyRules.localizedDescription)
                return
            }
            ruleSet = remoteConflict
            rules = merged.map { KokoroCustomRuleDraft(type: $0.type, payload: $0.payload, target: $0.target) }
            onUpdate(remoteConflict)
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
            let state = try await KokoroAPI.customRules()
            guard let remote = state.sets.first(where: { $0.id == ruleSet.id }) else {
                throw KokoroAPIError.http(status: 404, detail: nil)
            }
            return remote
        }

        private func apply(_ updated: KokoroRuleSet) {
            ruleSet = updated
            rules = updated.rules.map(KokoroCustomRuleDraft.init)
            onUpdate(updated)
        }

        private func clearConflict() {
            remoteConflict = nil
            showConflictResolution = false
        }
    }
#endif
