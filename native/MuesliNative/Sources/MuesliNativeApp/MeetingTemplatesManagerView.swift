import SwiftUI
import MuesliCore

struct MeetingTemplatesManagerView: View {
    let appState: AppState
    let controller: MuesliController
    let onClose: () -> Void

    @State private var isCreatingTemplate = false
    @State private var editingTemplateID: String?
    @State private var draftTemplateName = ""
    @State private var draftTemplatePrompt = ""
    @State private var draftTemplateIcon = MeetingTemplates.customIconFallback
    @State private var showNameValidationError = false
    @State private var showPromptValidationError = false
    @State private var templateToDelete: CustomMeetingTemplate?
    @State private var isEditingTitlePrompt = false
    @State private var draftTitlePrompt = ""
    @State private var showTitlePromptValidationError = false

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(.templateManagerTitle, config: appState.config))
                        .font(MuesliTheme.title2())
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(L10n.text(.templateManagerSubtitle, config: appState.config))
                        .font(MuesliTheme.callout())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }

                Spacer()

                HStack(spacing: MuesliTheme.spacing8) {
                    if isEditingTemplateInProgress {
                        actionButton(L10n.text(.sidebarCancel, config: appState.config), systemImage: "xmark") {
                            resetTemplateEditor()
                        }
                    } else {
                        actionButton(L10n.text(.templateManagerNew, config: appState.config), systemImage: "plus") {
                            beginCreatingTemplate()
                        }
                    }

                    actionButton(L10n.text(.templateManagerDone, config: appState.config), systemImage: "checkmark") {
                        onClose()
                    }
                    .disabled(isEditingTemplateInProgress)
                    .opacity(isEditingTemplateInProgress ? 0.55 : 1)
                    .help(isEditingTemplateInProgress ? L10n.text(.templateManagerFinishEditingHelp, config: appState.config) : L10n.text(.templateManagerCloseHelp, config: appState.config))
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                    customTemplatesSection
                    builtInTemplatesSection
                    systemPromptsSection

                    if isCreatingTemplate || editingTemplateID != nil {
                        customTemplateEditor
                    } else if isEditingTitlePrompt {
                        titlePromptEditor
                    }
                }
                .padding(.bottom, MuesliTheme.spacing4)
            }
        }
        .padding(MuesliTheme.spacing24)
        .frame(minWidth: 760, minHeight: 520)
        .background(MuesliTheme.backgroundBase)
        .alert(
            "\(L10n.text(.sidebarDelete, config: appState.config)) \"\(templateToDelete?.name ?? "")\"?",
            isPresented: Binding(
                get: { templateToDelete != nil },
                set: { if !$0 { templateToDelete = nil } }
            )
        ) {
            Button(L10n.text(.sidebarCancel, config: appState.config), role: .cancel) {
                templateToDelete = nil
            }
            Button(L10n.text(.sidebarDelete, config: appState.config), role: .destructive) {
                guard let template = templateToDelete else { return }
                controller.deleteCustomMeetingTemplate(id: template.id)
                if editingTemplateID == template.id {
                    resetTemplateEditor()
                }
                templateToDelete = nil
            }
        } message: {
            Text(L10n.text(.templateManagerDeleteMessage, config: appState.config))
        }
    }

    @ViewBuilder
    private var builtInTemplatesSection: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            Text(L10n.text(.meetingBuiltInTemplates, config: appState.config))
                .font(MuesliTheme.captionMedium())
                .foregroundStyle(MuesliTheme.textPrimary)

            ForEach(controller.builtInMeetingTemplates()) { template in
                builtInTemplateRow(template)
            }
        }
    }

    @ViewBuilder
    private var customTemplatesSection: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            Text(L10n.text(.meetingCustomTemplates, config: appState.config))
                .font(MuesliTheme.captionMedium())
                .foregroundStyle(MuesliTheme.textPrimary)

            if controller.customMeetingTemplates().isEmpty {
                emptyCustomState
            } else {
                ForEach(controller.customMeetingTemplates()) { template in
                    customTemplateRow(template)
                }
            }
        }
    }

    @ViewBuilder
    private var systemPromptsSection: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            Text(L10n.text(.templateManagerSystemPrompts, config: appState.config))
                .font(MuesliTheme.captionMedium())
                .foregroundStyle(MuesliTheme.textPrimary)

            meetingTitlePromptRow
        }
    }

    @ViewBuilder
    private var emptyCustomState: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Image(systemName: MeetingTemplates.customIconFallback)
                .font(.system(size: 11))
                .foregroundStyle(MuesliTheme.textTertiary)
            Text(L10n.text(.templateManagerEmpty, config: appState.config))
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textTertiary)
        }
        .padding(.horizontal, MuesliTheme.spacing12)
        .padding(.vertical, 10)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func builtInTemplateRow(_ template: MeetingTemplateDefinition) -> some View {
        let isVisible = controller.isBuiltInMeetingTemplateVisible(id: template.id)
        let isDefault = appState.config.defaultMeetingTemplateID == template.id
        let isAutoTarget = appState.config.autoTemplateTargetID == template.id

        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: template.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(MuesliTheme.accent)
                        Text(template.title)
                            .font(MuesliTheme.captionMedium())
                            .foregroundStyle(MuesliTheme.textPrimary)
                        statusPills(isDefault: isDefault, isAutoTarget: isAutoTarget)
                    }
                    Text(template.promptBody)
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: MuesliTheme.spacing8) {
                    Toggle(
                        L10n.text(.templateManagerVisible, config: appState.config),
                        isOn: Binding(
                            get: { controller.isBuiltInMeetingTemplateVisible(id: template.id) },
                            set: { controller.setBuiltInMeetingTemplateVisibility(id: template.id, isVisible: $0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)

                    actionButton(L10n.text(.templateManagerUseAsDefault, config: appState.config), systemImage: "star") {
                        controller.useTemplateAsDefault(id: template.id)
                    }
                    .disabled(!isVisible)
                    .opacity(isVisible ? 1 : 0.55)
                }
            }
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func customTemplateRow(_ template: CustomMeetingTemplate) -> some View {
        let isDefault = appState.config.defaultMeetingTemplateID == template.id
        let isAutoTarget = appState.config.autoTemplateTargetID == template.id
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: template.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(MuesliTheme.accent)
                        Text(template.name)
                            .font(MuesliTheme.captionMedium())
                            .foregroundStyle(MuesliTheme.textPrimary)
                        statusPills(isDefault: isDefault, isAutoTarget: isAutoTarget)
                    }
                    Text(template.prompt)
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                HStack(spacing: MuesliTheme.spacing8) {
                    actionButton(L10n.text(.templateManagerUseAsDefault, config: appState.config), systemImage: "star") {
                        controller.useTemplateAsDefault(id: template.id)
                    }
                    actionButton(L10n.text(.templateManagerEdit, config: appState.config), systemImage: "pencil") {
                        beginEditingTemplate(template)
                    }
                    actionButton(L10n.text(.sidebarDelete, config: appState.config), systemImage: "trash", role: .destructive) {
                        templateToDelete = template
                    }
                }
            }
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statusPills(isDefault: Bool, isAutoTarget: Bool) -> some View {
        if isDefault || isAutoTarget {
            HStack(spacing: 6) {
                if isDefault {
                    statusPill(L10n.text(.templateManagerDefaultBadge, config: appState.config))
                }
                if isAutoTarget {
                    statusPill(L10n.text(.templateManagerAutoBadge, config: appState.config))
                }
            }
        }
    }

    private func statusPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MuesliTheme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(MuesliTheme.accentSubtle)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var meetingTitlePromptRow: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 10))
                            .foregroundStyle(MuesliTheme.accent)
                        Text(L10n.text(.templateManagerMeetingTitlePrompt, config: appState.config))
                            .font(MuesliTheme.captionMedium())
                            .foregroundStyle(MuesliTheme.textPrimary)
                    }
                    Text(L10n.text(.templateManagerMeetingTitlePromptDescription, config: appState.config))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                    Text(controller.meetingTitlePrompt())
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .lineLimit(3)
                }
                Spacer()
                HStack(spacing: MuesliTheme.spacing8) {
                    actionButton(L10n.text(.templateManagerEdit, config: appState.config), systemImage: "pencil") {
                        beginEditingTitlePrompt()
                    }
                    actionButton(L10n.text(.templateManagerRestoreDefault, config: appState.config), systemImage: "arrow.uturn.backward") {
                        controller.resetMeetingTitlePrompt()
                        if isEditingTitlePrompt {
                            resetTitlePromptEditor()
                        }
                    }
                    .help(L10n.text(.templateManagerRestoreDefaultHelp, config: appState.config))
                }
            }
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var customTemplateEditor: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            Text(isCreatingTemplate ? L10n.text(.templateManagerNewTitle, config: appState.config) : L10n.text(.templateManagerEditTitle, config: appState.config))
                .font(MuesliTheme.captionMedium())
                .foregroundStyle(MuesliTheme.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text(.templateManagerName, config: appState.config))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                TextField(L10n.text(.templateManagerNamePlaceholder, config: appState.config), text: $draftTemplateName)
                    .textFieldStyle(.roundedBorder)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                showNameValidationError ? MuesliTheme.recording.opacity(0.75) : .clear,
                                lineWidth: 1
                            )
                    }
                    .onChange(of: draftTemplateName) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            showNameValidationError = false
                        }
                    }
                if showNameValidationError {
                    Text(L10n.text(.templateManagerNameValidation, config: appState.config))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.recording)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text(.templateManagerIcon, config: appState.config))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                customIconPicker
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text(.templateManagerPrompt, config: appState.config))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                TextEditor(text: $draftTemplatePrompt)
                    .font(.system(size: 12))
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .padding(MuesliTheme.spacing8)
                    .background(MuesliTheme.backgroundBase)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                            .strokeBorder(
                                showPromptValidationError ? MuesliTheme.recording.opacity(0.75) : MuesliTheme.surfaceBorder,
                                lineWidth: 1
                            )
                    )
                    .onChange(of: draftTemplatePrompt) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            showPromptValidationError = false
                        }
                    }
                if showPromptValidationError {
                    Text(L10n.text(.templateManagerPromptValidation, config: appState.config))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.recording)
                }
            }

            HStack {
                Spacer()
                actionButton(
                    isCreatingTemplate ? L10n.text(.templateManagerCreate, config: appState.config) : L10n.text(.templateManagerSave, config: appState.config),
                    systemImage: isCreatingTemplate ? "plus.circle" : "checkmark.circle"
                ) {
                    saveTemplateEditor()
                }
            }
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.surfacePrimary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var titlePromptEditor: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            Text(L10n.text(.templateManagerMeetingTitlePromptEditTitle, config: appState.config))
                .font(MuesliTheme.captionMedium())
                .foregroundStyle(MuesliTheme.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text(.templateManagerPrompt, config: appState.config))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                TextEditor(text: $draftTitlePrompt)
                    .font(.system(size: 12))
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .padding(MuesliTheme.spacing8)
                    .background(MuesliTheme.backgroundBase)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                            .strokeBorder(
                                showTitlePromptValidationError ? MuesliTheme.recording.opacity(0.75) : MuesliTheme.surfaceBorder,
                                lineWidth: 1
                            )
                    )
                    .onChange(of: draftTitlePrompt) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            showTitlePromptValidationError = false
                        }
                    }
                if showTitlePromptValidationError {
                    Text(L10n.text(.templateManagerPromptValidation, config: appState.config))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.recording)
                }
            }

            HStack {
                Spacer()
                actionButton(L10n.text(.templateManagerSave, config: appState.config), systemImage: "checkmark.circle") {
                    saveTitlePromptEditor()
                }
            }
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.surfacePrimary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func beginCreatingTemplate() {
        resetTitlePromptEditor()
        isCreatingTemplate = true
        editingTemplateID = nil
        draftTemplateName = ""
        draftTemplatePrompt = ""
        draftTemplateIcon = MeetingTemplates.customIconFallback
        clearValidationErrors()
    }

    private func beginEditingTemplate(_ template: CustomMeetingTemplate) {
        resetTitlePromptEditor()
        isCreatingTemplate = false
        editingTemplateID = template.id
        draftTemplateName = template.name
        draftTemplatePrompt = template.prompt
        draftTemplateIcon = MeetingTemplates.normalizedCustomIcon(named: template.icon)
        clearValidationErrors()
    }

    private func resetTemplateEditor() {
        resetTitlePromptEditor()
        isCreatingTemplate = false
        editingTemplateID = nil
        draftTemplateName = ""
        draftTemplatePrompt = ""
        draftTemplateIcon = MeetingTemplates.customIconFallback
        clearValidationErrors()
    }

    private func beginEditingTitlePrompt() {
        resetTemplateEditor()
        isEditingTitlePrompt = true
        draftTitlePrompt = controller.meetingTitlePrompt()
        showTitlePromptValidationError = false
    }

    private func resetTitlePromptEditor() {
        isEditingTitlePrompt = false
        draftTitlePrompt = ""
        showTitlePromptValidationError = false
    }

    private func saveTemplateEditor() {
        let trimmedName = draftTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = draftTemplatePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        showNameValidationError = trimmedName.isEmpty
        showPromptValidationError = trimmedPrompt.isEmpty
        guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty else { return }

        if let editingTemplateID {
            controller.updateCustomMeetingTemplate(
                id: editingTemplateID,
                name: trimmedName,
                prompt: trimmedPrompt,
                icon: draftTemplateIcon
            )
        } else {
            controller.createCustomMeetingTemplate(
                name: trimmedName,
                prompt: trimmedPrompt,
                icon: draftTemplateIcon
            )
        }
        resetTemplateEditor()
    }

    private var isEditingTemplateInProgress: Bool {
        isCreatingTemplate || editingTemplateID != nil || isEditingTitlePrompt
    }

    private func saveTitlePromptEditor() {
        let trimmedPrompt = draftTitlePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        showTitlePromptValidationError = trimmedPrompt.isEmpty
        guard !trimmedPrompt.isEmpty else { return }
        controller.updateMeetingTitlePrompt(trimmedPrompt)
        resetTitlePromptEditor()
    }

    private func clearValidationErrors() {
        showNameValidationError = false
        showPromptValidationError = false
    }

    @ViewBuilder
    private var customIconPicker: some View {
        let columns = [
            GridItem(.adaptive(minimum: 36, maximum: 36), spacing: 6)
        ]

        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(spacing: MuesliTheme.spacing8) {
                Image(systemName: draftTemplateIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MuesliTheme.accent)
                    .frame(width: 24, height: 24)
                    .background(MuesliTheme.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                Text(selectedIconLabel)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(MeetingTemplates.customIconOptions) { icon in
                    Button {
                        draftTemplateIcon = icon.symbolName
                    } label: {
                        Image(systemName: icon.symbolName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(
                                draftTemplateIcon == icon.symbolName
                                    ? MuesliTheme.accent
                                    : MuesliTheme.textSecondary
                            )
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(
                                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                    .fill(
                                        draftTemplateIcon == icon.symbolName
                                            ? MuesliTheme.accent.opacity(0.12)
                                            : MuesliTheme.backgroundRaised
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                    .strokeBorder(
                                        draftTemplateIcon == icon.symbolName
                                            ? MuesliTheme.accent.opacity(0.35)
                                            : MuesliTheme.surfaceBorder,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(icon.label)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedIconLabel: String {
        MeetingTemplates.customIconOptions.first(where: { $0.symbolName == draftTemplateIcon })?.label ?? L10n.text(.templateManagerCustom, config: appState.config)
    }

    @ViewBuilder
    private func actionButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let isDestructive = role == .destructive
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isDestructive ? MuesliTheme.recording : MuesliTheme.textPrimary)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 7)
            .background(isDestructive ? MuesliTheme.recording.opacity(0.1) : MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(
                        isDestructive ? MuesliTheme.recording.opacity(0.2) : MuesliTheme.surfaceBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
