#if !os(tvOS)
    import Library
    import SwiftUI

    @MainActor
    struct KokoroConnectionRuleView: View {
        @Environment(\.dismiss) private var dismiss
        @StateObject private var viewModel = KokoroCustomRulesViewModel()
        let source: KokoroConnectionRuleSource

        var body: some View {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else if !viewModel.isSignedIn {
                    FormView {
                        Section {
                            FormButton {
                                Task { await viewModel.signIn() }
                            } label: {
                                Label("Sign in with Kokoro", systemImage: "person.crop.circle.badge.checkmark")
                            }
                        }
                    }
                } else if let options = viewModel.options, viewModel.ruleSet != nil {
                    let suggestions = source.suggestions(options: options)
                    if let suggestion = suggestions.first {
                        KokoroCustomRuleEditView(
                            title: String(localized: "Create Routing Rule"),
                            draft: KokoroCustomRuleDraft(type: suggestion.type, payload: suggestion.payload, target: suggestion.target),
                            options: options,
                            connectionSuggestions: suggestions,
                            footer: String(localized: "This rule will be saved first in your Kokoro custom rules. After saving, update your Kokoro subscription profile and reconnect to apply it."),
                            validateDraft: validationMessage,
                            onSubmit: viewModel.saveConnectionRule
                        )
                    } else {
                        FormView {
                            Text("No supported domain or IP rule can be created from this connection.")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    FormView {
                        Section {
                            Text("The default rule set is unavailable.")
                                .foregroundStyle(.secondary)
                            FormButton {
                                Task { await viewModel.reload() }
                            } label: {
                                Label("Reload", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Create Routing Rule")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .task { await viewModel.loadIfNeeded() }
            .onDisappear { viewModel.cancelSignIn() }
            .alert($viewModel.alert)
            .onChange(of: viewModel.showConflictResolution) { hasConflict in
                guard hasConflict else { return }
                viewModel.showConflictResolution = false
                viewModel.alert = AlertState(errorMessage: String(localized: "The custom rules changed elsewhere. Review this rule and tap Save again to add it to the latest rules."))
            }
            .toolbar {
                // The loaded editor supplies its own Cancel and Save actions.
                if !hasEditableRule {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }

        private var hasEditableRule: Bool {
            guard !viewModel.isLoading, viewModel.isSignedIn,
                  viewModel.ruleSet != nil, let options = viewModel.options else { return false }
            return !source.suggestions(options: options).isEmpty
        }

        private func validationMessage(_ draft: KokoroCustomRuleDraft) -> String? {
            guard let options = viewModel.options,
                  let ruleSet = viewModel.remoteConflict ?? viewModel.ruleSet else { return nil }
            do {
                _ = try KokoroCustomRulesValidator.prepending(draft.input, to: ruleSet.rules.map(\.input), options: options)
                return nil
            } catch {
                return error.localizedDescription
            }
        }
    }
#endif
