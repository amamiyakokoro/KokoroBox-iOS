#if !os(tvOS)
    import Library
    import SwiftUI

    @MainActor
    public struct KokoroCustomRulesView: View {
        @Environment(\.dismiss) private var dismiss
        @StateObject private var viewModel = KokoroCustomRulesViewModel()
        @State private var showCreateSet = false

        public init() {}

        public var body: some View {
            Group {
                if viewModel.isLoading, !viewModel.isSignedIn {
                    ProgressView()
                } else if !viewModel.isSignedIn {
                    signedOutContent
                } else {
                    FormView {
                        setsSection
                        createSection
                    }
                }
            }
            .navigationTitle("Custom Rules")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
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
            .platformSheet(isPresented: $showCreateSet, size: .small) {
                KokoroRuleSetNameView(title: String(localized: "New Rule Set"), initialName: "") { name in
                    await viewModel.createSet(name: name)
                }
            }
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

        @ViewBuilder
        private var setsSection: some View {
            Section {
                if viewModel.sets.isEmpty {
                    Text("No rule sets")
                        .foregroundStyle(.secondary)
                } else if let options = viewModel.options {
                    ForEach(viewModel.sets) { ruleSet in
                        FormNavigationLink {
                            KokoroRuleSetView(
                                ruleSet: ruleSet,
                                options: options,
                                onUpdate: viewModel.update,
                                onDelete: viewModel.remove
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: ruleSet.name)
                                    .fontWeight(.medium)
                                Text("\(ruleSet.rules.count) rules · revision \(ruleSet.revision)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Rule Sets")
            } footer: {
                Text("Only the default rule set is included in generated Kokoro configurations.")
            }
        }

        @ViewBuilder
        private var createSection: some View {
            if let options = viewModel.options {
                Section {
                    FormButton {
                        showCreateSet = true
                    } label: {
                        Label("New Rule Set", systemImage: "plus")
                    }
                    .disabled(viewModel.isLoading || viewModel.sets.count >= options.maximumRuleSets)
                } footer: {
                    Text("Up to \(options.maximumRuleSets) rule sets, with \(options.maximumRulesPerSet) rules in each set.")
                }
            }
        }
    }

    @MainActor
    private struct KokoroRuleSetView: View {
        @Environment(\.dismiss) private var dismiss
        @StateObject private var viewModel: KokoroRuleSetViewModel
        @State private var editingRule: KokoroCustomRuleDraft?
        @State private var isAddingRule = false
        @State private var showRename = false
        @State private var showDeleteConfirmation = false
        #if os(iOS)
            @State private var editMode: EditMode = .inactive
        #endif

        init(
            ruleSet: KokoroRuleSet,
            options: KokoroCustomRulesOptions,
            onUpdate: @escaping (KokoroRuleSet) -> Void,
            onDelete: @escaping (Int) -> Void
        ) {
            _viewModel = StateObject(wrappedValue: KokoroRuleSetViewModel(
                ruleSet: ruleSet,
                options: options,
                onUpdate: onUpdate,
                onDelete: onDelete
            ))
        }

        var body: some View {
            FormView {
                rulesSection
                statusSection
            }
            .navigationTitle(viewModel.ruleSet.name)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .environment(\.editMode, $editMode)
            #endif
            .disabled(viewModel.isSaving)
            .toolbar { toolbarContent }
            .alert($viewModel.alert)
            .platformSheet(isPresented: $isAddingRule, size: .small) {
                KokoroCustomRuleEditView(
                    title: String(localized: "New Rule"),
                    draft: newDraft,
                    options: viewModel.options
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
            .platformSheet(item: $editingRule, size: .small) { original in
                KokoroCustomRuleEditView(
                    title: String(localized: "Edit Rule"),
                    draft: original,
                    options: viewModel.options
                ) { updated in
                    if let index = viewModel.rules.firstIndex(where: { $0.id == updated.id }) {
                        viewModel.rules[index] = updated
                    }
                }
            }
            .platformSheet(isPresented: $showRename, size: .small) {
                KokoroRuleSetNameView(
                    title: String(localized: "Rename Rule Set"),
                    initialName: viewModel.ruleSet.name
                ) { name in
                    await viewModel.rename(to: name)
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
            .confirmationDialog(
                "Delete Rule Set?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task {
                        if await viewModel.delete() { dismiss() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes the rule set from Kokoro and cannot be undone.")
            }
        }

        @ToolbarContentBuilder
        private var toolbarContent: some ToolbarContent {
            #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton().disabled(viewModel.rules.isEmpty)
                }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button("Save") { Task { await viewModel.save() } }
                    .disabled(viewModel.isSaving || viewModel.validationMessage != nil)
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Rename") { showRename = true }
                        .disabled(viewModel.ruleSet.isDefault)
                    Button("Delete", role: .destructive) { showDeleteConfirmation = true }
                        .disabled(viewModel.ruleSet.isDefault)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
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
            Section("Status") {
                FormTextItem("Revision", String(viewModel.ruleSet.revision))
                FormTextItem("Rule Count", String(viewModel.rules.count))
            }
        }

        private var newDraft: KokoroCustomRuleDraft {
            let type = viewModel.options.ruleTypes.first ?? "DOMAIN-SUFFIX"
            let target = viewModel.options.targets.first(where: { type != "MATCH" || $0 != "REJECT" }) ?? "DIRECT"
            let payload = type == "RULE-SET" ? viewModel.options.domainRuleProviders.first?.name : nil
            return KokoroCustomRuleDraft(type: type, payload: payload, target: target)
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

    @MainActor
    private struct KokoroRuleSetNameView: View {
        @Environment(\.dismiss) private var dismiss
        @State private var name: String
        @State private var isSaving = false
        let title: String
        let onSave: (String) async -> Bool

        init(title: String, initialName: String, onSave: @escaping (String) async -> Bool) {
            self.title = title
            _name = State(initialValue: initialName)
            self.onSave = onSave
        }

        var body: some View {
            Form {
                Section("Name") {
                    TextField("Required", text: $name)
                }
            }
            .navigationTitle(title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #elseif os(macOS)
                .formStyle(.grouped)
            #endif
            .disabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            Task {
                                isSaving = true
                                if await onSave(normalized) { dismiss() }
                                isSaving = false
                            }
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
#endif
