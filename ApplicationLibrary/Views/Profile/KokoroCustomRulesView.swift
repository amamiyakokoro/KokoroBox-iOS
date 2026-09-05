#if !os(tvOS)
    import Library
    import SwiftUI

    @MainActor
    public struct KokoroCustomRulesView: View {
        @Environment(\.dismiss) private var dismiss
        @StateObject private var viewModel = KokoroCustomRulesViewModel()
        @State private var editingRule: KokoroCustomRuleDraft?
        @State private var isAddingRule = false
        #if os(iOS)
            @State private var editMode: EditMode = .inactive
        #endif

        public init() {}

        public var body: some View {
            Group {
                if viewModel.isLoading, !viewModel.isSignedIn {
                    ProgressView()
                } else if !viewModel.isSignedIn {
                    signedOutContent
                } else if viewModel.ruleSet != nil, viewModel.options != nil {
                    rulesContent
                } else if viewModel.isLoading {
                    ProgressView()
                } else {
                    unavailableContent
                }
            }
            .navigationTitle("Custom Rules")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .environment(\.editMode, $editMode)
            #endif
            #if os(macOS)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            #endif
            .task { await viewModel.loadIfNeeded() }
            .onDisappear { viewModel.cancelSignIn() }
            .refreshable {
                if viewModel.isSignedIn { await viewModel.reload() }
            }
            .alert($viewModel.alert)
            .platformSheet(isPresented: $isAddingRule, size: .small) {
                if let options = viewModel.options {
                    KokoroCustomRuleEditView(
                        title: String(localized: "New Rule"),
                        draft: newDraft,
                        options: options
                    ) { rule in
                        if rule.type == "MATCH" {
                            viewModel.rules.append(rule)
                        } else if let match = viewModel.rules.firstIndex(where: { $0.type == "MATCH" }) {
                            viewModel.rules.insert(rule, at: match)
                        } else {
                            viewModel.rules.append(rule)
                        }
                    }
                }
            }
            .platformSheet(item: $editingRule, size: .small) { original in
                if let options = viewModel.options {
                    KokoroCustomRuleEditView(
                        title: String(localized: "Edit Rule"),
                        draft: original,
                        options: options
                    ) { updated in
                        if let index = viewModel.rules.firstIndex(where: { $0.id == updated.id }) {
                            viewModel.rules[index] = updated
                        }
                    }
                }
            }
            .platformSheet(
                isPresented: $viewModel.showConflictResolution,
                size: PlatformSheetSize(minWidth: 560, minHeight: 520)
            ) {
                if let remote = viewModel.remoteConflict {
                    KokoroRulesConflictView(
                        remote: remote,
                        localRuleCount: viewModel.rules.count,
                        onReapply: viewModel.reapplyLocalChanges,
                        onMerge: viewModel.mergeChanges,
                        onUseRemote: viewModel.discardLocalChanges
                    )
                }
            }
        }

        @ToolbarContentBuilder
        private var rulesToolbarContent: some ToolbarContent {
            #if os(macOS)
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await viewModel.reload() }
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading || viewModel.isSaving)
                }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button("Save") { Task { await viewModel.save() } }
                    .disabled(viewModel.isSaving || viewModel.validationMessage != nil)
            }
        }

        private var rulesContent: some View {
            FormView {
                rulesSection
                statusSection
            }
            .disabled(viewModel.isSaving)
            .toolbar { rulesToolbarContent }
        }

        private var unavailableContent: some View {
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

        private var rulesSection: some View {
            Section {
                if viewModel.rules.isEmpty {
                    Text("No rules")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.rules) { rule in
                        Button {
                            editingRule = rule
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(verbatim: rule.type)
                                        .fontWeight(.medium)
                                    if !rule.payload.isEmpty {
                                        Text(verbatim: rule.payload)
                                            .lineLimit(1)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(verbatim: rule.target)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        #if os(macOS)
                            .buttonStyle(.plain)
                        #else
                            .foregroundStyle(.primary)
                        #endif
                    }
                    .onMove { viewModel.rules.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { viewModel.rules.remove(atOffsets: $0) }
                }
            } header: {
                HStack {
                    Text("Rules")
                    Spacer()
                    #if os(iOS)
                        EditButton()
                            .disabled(viewModel.rules.isEmpty)
                    #endif
                    Button {
                        isAddingRule = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(!viewModel.canAddRule)
                    #if os(macOS)
                        .buttonStyle(.plain)
                    #endif
                }
            } footer: {
                if let validationMessage = viewModel.validationMessage {
                    Text(verbatim: validationMessage).foregroundStyle(.red)
                } else {
                    Text("Rules run from top to bottom. MATCH can appear once and must be last.")
                }
            }
        }

        private var statusSection: some View {
            Section {
                FormTextItem("Revision", String(viewModel.ruleSet?.revision ?? 0))
                FormTextItem("Rule Count", String(viewModel.rules.count))
            } header: {
                Text("Status")
            } footer: {
                Text("These rules override the default routing behavior in generated Kokoro configurations.")
            }
        }

        private var newDraft: KokoroCustomRuleDraft {
            let type = viewModel.options?.ruleTypes.first ?? "DOMAIN-SUFFIX"
            let targets = viewModel.options?.targets ?? []
            let target = targets.first(where: { type != "MATCH" || $0 != "REJECT" }) ?? "DIRECT"
            let payload = type == "RULE-SET" ? viewModel.options?.domainRuleProviders.first?.name : nil
            return KokoroCustomRuleDraft(type: type, payload: payload, target: target)
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
                    Text("Sign in securely with osu! in your system browser to manage Custom Rules.")
                }
            }
        }
    }

    @MainActor
    private struct KokoroRulesConflictView: View {
        @Environment(\.dismiss) private var dismiss
        let remote: KokoroRuleSet
        let localRuleCount: Int
        let onReapply: () -> Void
        let onMerge: () -> Void
        let onUseRemote: () -> Void

        var body: some View {
            FormView {
                Section {
                    FormTextItem("Remote Revision", String(remote.revision))
                    FormTextItem("Remote Rule Count", String(remote.rules.count))
                    FormTextItem("Local Rule Count", String(localRuleCount))
                } footer: {
                    Text("The rules changed on another device or on the website. Review the remote version before choosing how to continue.")
                }

                Section("Remote Rules") {
                    if remote.rules.isEmpty {
                        Text("No rules").foregroundStyle(.secondary)
                    } else {
                        ForEach(remote.rules) { rule in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(verbatim: rule.type).fontWeight(.medium)
                                    Spacer()
                                    Text(verbatim: rule.target).foregroundStyle(.secondary)
                                }
                                if let payload = rule.payload, !payload.isEmpty {
                                    Text(verbatim: payload)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    FormButton {
                        onReapply()
                        dismiss()
                    } label: {
                        Text("Reapply My Changes")
                    }
                    FormButton {
                        onMerge()
                        dismiss()
                    } label: {
                        Text("Merge and Review")
                    }
                    FormButton(role: .destructive) {
                        onUseRemote()
                        dismiss()
                    } label: {
                        Text("Use Remote Version")
                    }
                } footer: {
                    Text("Reapply and merge update the base revision only. Review the draft and tap Save to submit it.")
                }
            }
            .navigationTitle("Rule Set Changed")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private struct KokoroCustomRuleEditView: View {
        @Environment(\.dismiss) private var dismiss
        @State private var draft: KokoroCustomRuleDraft
        let title: String
        let options: KokoroCustomRulesOptions
        let onSave: (KokoroCustomRuleDraft) -> Void

        init(
            title: String,
            draft: KokoroCustomRuleDraft,
            options: KokoroCustomRulesOptions,
            onSave: @escaping (KokoroCustomRuleDraft) -> Void
        ) {
            self.title = title
            _draft = State(initialValue: draft)
            self.options = options
            self.onSave = onSave
        }

        var body: some View {
            Form {
                Section {
                    FormPicker(
                        String(localized: "Type"),
                        options: options.ruleTypes.map { FormPickerOption($0, $0) },
                        selection: $draft.type
                    )
                    FormPicker(
                        String(localized: "Target"),
                        options: availableTargets.map { FormPickerOption($0, $0) },
                        selection: $draft.target
                    )
                }

                if draft.type == "RULE-SET" {
                    Section("Rule Provider") {
                        FormPicker(
                            String(localized: "Provider"),
                            options: options.domainRuleProviders.map { FormPickerOption($0.name, $0.name) },
                            selection: $draft.payload
                        )
                    }
                } else if draft.type != "MATCH" {
                    Section("Value") {
                        TextField("Required", text: $draft.payload)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                    }
                }

                if let validationMessage {
                    Section {
                        Text(verbatim: validationMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #elseif os(macOS)
                .formStyle(.grouped)
            #endif
            .onChange(of: draft.type) { newType in
                if newType == "MATCH" {
                    draft.payload = ""
                } else if newType == "RULE-SET" {
                    draft.payload = options.domainRuleProviders.first?.name ?? ""
                }
                if !availableTargets.contains(draft.target) {
                    draft.target = availableTargets.first ?? ""
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(validationMessage != nil)
                }
            }
        }

        private var availableTargets: [String] {
            draft.type == "MATCH" ? options.targets.filter { $0 != "REJECT" } : options.targets
        }

        private var validationMessage: String? {
            do {
                try KokoroCustomRulesValidator.validate([draft.input], options: options)
                return nil
            } catch {
                return error.localizedDescription
            }
        }
    }

#endif
