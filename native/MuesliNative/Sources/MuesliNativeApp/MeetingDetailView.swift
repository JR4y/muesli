import SwiftUI
import MuesliCore

private enum MeetingDocumentMode: Hashable {
    case notes
    case transcript
}

struct MeetingDetailView: View {
    let meeting: MeetingRecord?
    let controller: MuesliController
    let appState: AppState
    let onBack: (() -> Void)?
    let backLabel: String
    @State private var isSummarizing = false
    @State private var isEditingNotes = false
    @State private var editableTitle: String
    @State private var editableNotes: String
    @State private var pendingTemplateID: String
    @State private var documentMode: MeetingDocumentMode
    @State private var titleSaveTask: DispatchWorkItem?
    @State private var notesSaveTask: DispatchWorkItem?
    @State private var summaryErrorMessage: String?
    @State private var calendarAssociationErrorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var isCalendarEventPickerPresented = false
    @State private var nearbyCalendarEvents: [UnifiedCalendarEvent] = []

    init(
        meeting: MeetingRecord?,
        controller: MuesliController,
        appState: AppState,
        onBack: (() -> Void)? = nil,
        backLabel: String = "Back to Meetings"
    ) {
        self.meeting = meeting
        self.controller = controller
        self.appState = appState
        self.onBack = onBack
        self.backLabel = backLabel
        let initialTemplateID = meeting.map { controller.meetingTemplateSnapshot(for: $0).id } ?? controller.defaultMeetingTemplate().id
        _editableTitle = State(initialValue: meeting?.title ?? "")
        _editableNotes = State(initialValue: meeting.map { Self.notesContent(for: $0) } ?? "")
        _pendingTemplateID = State(initialValue: initialTemplateID)
        _documentMode = State(initialValue: meeting.map(Self.defaultDocumentMode(for:)) ?? .notes)
    }

    var body: some View {
        Group {
            if let meeting {
                VStack(alignment: .leading, spacing: 0) {
                    header(meeting)

                    Divider()
                        .background(MuesliTheme.surfaceBorder)

                    content(for: meeting)
                }
                .background(MuesliTheme.backgroundBase)
                .onChange(of: meeting.id) { _, _ in
                    syncLocalState(with: meeting)
                }
                .onChange(of: appState.config.customMeetingTemplates) { _, _ in
                    syncPendingTemplateSelectionIfNeeded(for: meeting)
                }
            } else {
                VStack(spacing: MuesliTheme.spacing12) {
                    Text(L10n.text(.meetingNoSelectionTitle, config: appState.config))
                        .font(MuesliTheme.title3())
                        .foregroundStyle(MuesliTheme.textSecondary)
                    Text(L10n.text(.meetingNoSelectionMessage, config: appState.config))
                        .font(MuesliTheme.callout())
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MuesliTheme.backgroundBase)
            }
        }
        .alert(L10n.text(.meetingSummarySaveErrorTitle, config: appState.config), isPresented: summaryErrorBinding) {
            Button(L10n.text(.commonOK, config: appState.config), role: .cancel) {
                summaryErrorMessage = nil
            }
        } message: {
            Text(summaryErrorMessage ?? L10n.text(.meetingSummarySaveErrorMessage, config: appState.config))
        }
        .alert(L10n.text(.meetingCalendarAssociationFailedTitle, config: appState.config), isPresented: calendarAssociationErrorBinding) {
            Button(L10n.text(.commonOK, config: appState.config), role: .cancel) {
                calendarAssociationErrorMessage = nil
            }
        } message: {
            Text(calendarAssociationErrorMessage ?? L10n.text(.meetingCalendarAssociationFailedMessage, config: appState.config))
        }
        .alert(L10n.text(.meetingDeleteTitle, config: appState.config), isPresented: $showDeleteConfirmation) {
            Button(L10n.text(.sidebarDelete, config: appState.config), role: .destructive) {
                if let meeting {
                    controller.deleteMeeting(id: meeting.id)
                }
            }
            Button(L10n.text(.sidebarCancel, config: appState.config), role: .cancel) {}
        } message: {
            Text(L10n.text(.meetingDeleteMessage, config: appState.config))
        }
        .sheet(isPresented: $isCalendarEventPickerPresented) {
            if let meeting {
                calendarEventPickerSheet(for: meeting)
            }
        }
    }

    @ViewBuilder
    private func header(_ meeting: MeetingRecord) -> some View {
        let appliedTemplate = controller.meetingTemplateSnapshot(for: meeting)
        VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
            if let onBack {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text(backLabel)
                            .font(MuesliTheme.callout())
                    }
                    .foregroundStyle(MuesliTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: MuesliTheme.spacing24) {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                    TextField(L10n.text(.meetingTitlePlaceholder, config: appState.config), text: $editableTitle)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(MuesliTheme.textPrimary)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            controller.updateMeetingTitle(id: meeting.id, title: editableTitle)
                        }
                        .onChange(of: editableTitle) { _, _ in
                            debounceSaveTitle(meetingID: meeting.id)
                        }

                    HStack(spacing: MuesliTheme.spacing8) {
                        Text(formatMeta(meeting))
                            .font(MuesliTheme.callout())
                            .foregroundStyle(MuesliTheme.textSecondary)
                        calendarAssociationControl(for: meeting)
                        templateChip(for: appliedTemplate)
                    }
                }

                Spacer(minLength: MuesliTheme.spacing16)

                VStack(alignment: .trailing, spacing: 10) {
                    documentModePicker

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: MuesliTheme.spacing8) {
                            templateMenu(for: meeting, appliedTemplate: appliedTemplate)
                            recordingAction(for: meeting)
                            summaryAction(for: meeting)
                            editButton(for: meeting)
                            deleteButton
                        }

                        VStack(alignment: .trailing, spacing: MuesliTheme.spacing8) {
                            HStack(spacing: MuesliTheme.spacing8) {
                                templateMenu(for: meeting, appliedTemplate: appliedTemplate)
                                recordingAction(for: meeting)
                                summaryAction(for: meeting)
                            }
                            HStack(spacing: MuesliTheme.spacing8) {
                                editButton(for: meeting)
                                deleteButton
                            }
                        }
                    }
                }
            }

            if isRawTranscript(meeting) && documentMode == .notes {
                transcriptCTA
            }
        }
        .frame(maxWidth: 980, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func content(for meeting: MeetingRecord) -> some View {
        if isEditingNotes {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                contentToolbar(for: meeting)

                TextEditor(text: $editableNotes)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(MuesliTheme.spacing24)
                    .background(MuesliTheme.backgroundBase)
                    .frame(maxWidth: 980, maxHeight: .infinity, alignment: .topLeading)
                    .onChange(of: editableNotes) { _, _ in
                        debounceSaveNotes(meetingID: meeting.id)
                    }
            }
            .padding(.horizontal, 40)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                contentToolbar(for: meeting)

                ZStack {
                    MeetingNotesView(markdown: Self.notesContent(for: meeting))
                        .opacity(documentMode == .notes ? 1 : 0)
                        .allowsHitTesting(documentMode == .notes)
                        .accessibilityHidden(documentMode != .notes)

                    MeetingTranscriptView(transcript: meeting.rawTranscript)
                        .opacity(documentMode == .transcript ? 1 : 0)
                        .allowsHitTesting(documentMode == .transcript)
                        .accessibilityHidden(documentMode != .transcript)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var documentModePicker: some View {
        Picker("", selection: $documentMode) {
            Text(L10n.text(.meetingNotes, config: appState.config)).tag(MeetingDocumentMode.notes)
            Text(L10n.text(.meetingTranscript, config: appState.config)).tag(MeetingDocumentMode.transcript)
        }
        .pickerStyle(.segmented)
        .tint(MuesliTheme.accent)
        .frame(width: 220)
        .disabled(isEditingNotes)
    }

    @ViewBuilder
    private func summaryAction(for meeting: MeetingRecord) -> some View {
        if isSummarizing {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.text(.meetingSummarizing, config: appState.config))
                    .font(.system(size: 11))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
            .padding(.horizontal, MuesliTheme.spacing8)
        } else {
            iconButton("sparkles", label: primarySummaryActionLabel(for: meeting)) {
                isSummarizing = true
                let completion: (Result<Void, Error>) -> Void = { [meeting] result in
                    isSummarizing = false
                    switch result {
                    case .success:
                        if let updated = controller.meeting(id: meeting.id) {
                            syncLocalState(with: updated)
                        }
                    case .failure(let error):
                        syncPendingTemplateSelectionIfNeeded(
                            for: controller.meeting(id: meeting.id) ?? meeting
                        )
                        summaryErrorMessage = error.localizedDescription
                    }
                }
                if hasPendingTemplateChange(for: meeting) {
                    controller.applyMeetingTemplate(id: pendingTemplateID, to: meeting, completion: completion)
                } else {
                    controller.resummarize(meeting: meeting, completion: completion)
                }
            }
        }
    }

    @ViewBuilder
    private func editButton(for meeting: MeetingRecord) -> some View {
        iconButton(
            isEditingNotes ? "checkmark.circle" : "pencil",
            label: isEditingNotes ? L10n.text(.meetingDone, config: appState.config) : L10n.text(.meetingEdit, config: appState.config)
        ) {
            if isEditingNotes {
                notesSaveTask?.cancel()
                controller.updateMeetingNotes(id: meeting.id, notes: editableNotes)
            } else {
                documentMode = .notes
                editableNotes = Self.notesContent(for: meeting)
            }
            isEditingNotes.toggle()
        }
    }

    @ViewBuilder
    private func calendarAssociationControl(for meeting: MeetingRecord) -> some View {
        if meeting.calendarEventID == nil {
            Button {
                nearbyCalendarEvents = controller.suggestedCalendarEvents(for: meeting)
                isCalendarEventPickerPresented = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 10))
                    Text(L10n.text(.meetingAssociateEvent, config: appState.config))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(MuesliTheme.textSecondary)
                .padding(.horizontal, MuesliTheme.spacing8)
                .padding(.vertical, 4)
                .background(MuesliTheme.surfacePrimary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 5) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 10))
                Text(L10n.text(.meetingCalendarLinked, config: appState.config))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(MuesliTheme.success)
            .padding(.horizontal, MuesliTheme.spacing8)
            .padding(.vertical, 4)
            .background(MuesliTheme.success.opacity(0.12))
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private func recordingAction(for meeting: MeetingRecord) -> some View {
        if let savedRecordingPath = meeting.savedRecordingPath {
            iconButton("folder", label: L10n.text(.meetingShowRecording, config: appState.config)) {
                controller.revealMeetingRecordingInFinder(path: savedRecordingPath)
            }
        }
    }

    @ViewBuilder
    private func templateMenu(for meeting: MeetingRecord, appliedTemplate: MeetingTemplateSnapshot) -> some View {
        Menu {
            Button {
                pendingTemplateID = MeetingTemplates.autoID
            } label: {
                templateMenuItem(
                    title: MeetingTemplates.auto.title,
                    systemImage: MeetingTemplates.auto.icon,
                    isSelected: pendingTemplateID == MeetingTemplates.autoID
                )
            }

            Section(L10n.text(.meetingBuiltInTemplates, config: appState.config)) {
                ForEach(controller.builtInMeetingTemplates()) { template in
                    Button {
                        pendingTemplateID = template.id
                    } label: {
                        templateMenuItem(
                            title: template.title,
                            systemImage: template.icon,
                            isSelected: pendingTemplateID == template.id
                        )
                    }
                }
            }

            if !controller.customMeetingTemplates().isEmpty {
                Section(L10n.text(.meetingCustomTemplates, config: appState.config)) {
                    ForEach(controller.customMeetingTemplates()) { template in
                        Button {
                            pendingTemplateID = template.id
                        } label: {
                            let resolved = MeetingTemplates.customDefinition(from: template)
                            templateMenuItem(
                                title: template.name,
                                systemImage: resolved.icon,
                                isSelected: pendingTemplateID == template.id
                            )
                        }
                    }
                }
            }

            Divider()

            Button(L10n.text(.meetingManageTemplates, config: appState.config)) {
                controller.showMeetingTemplatesManager()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: iconName(forSelectionOn: meeting, appliedTemplate: appliedTemplate))
                    .font(.system(size: 10))
                Text(labelForSelection(on: meeting, appliedTemplate: appliedTemplate))
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
            }
            .foregroundStyle(MuesliTheme.textSecondary)
            .padding(.horizontal, MuesliTheme.spacing8)
            .padding(.vertical, 5)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func contentToolbar(for meeting: MeetingRecord) -> some View {
        HStack {
            Spacer()

            exportMenu(for: meeting)

            Button(action: {
                controller.copyToClipboard(activeCopyText(for: meeting))
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                    Text(copyButtonLabel)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(MuesliTheme.textPrimary)
                .padding(.horizontal, MuesliTheme.spacing12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .fill(MuesliTheme.accent.opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .strokeBorder(MuesliTheme.accent.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 980, alignment: .leading)
    }

    @ViewBuilder
    private func exportMenu(for meeting: MeetingRecord) -> some View {
        let currentContent: MeetingExportContent = documentMode == .transcript ? .transcript : .notes
        let currentLabel = documentMode == .transcript ? L10n.text(.meetingExportTranscript, config: appState.config) : L10n.text(.meetingExportNotes, config: appState.config)
        Menu {
            Button {
                MeetingExporter.export(meeting: meeting, content: currentContent)
            } label: {
                Label(currentLabel, systemImage: documentMode == .transcript ? "text.quote" : "doc.text")
            }
            Button {
                MeetingExporter.export(meeting: meeting, content: .fullMeeting)
            } label: {
                Label(L10n.text(.meetingExportFull, config: appState.config), systemImage: "doc.on.doc")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 10, weight: .semibold))
                Text(L10n.text(.meetingExport, config: appState.config))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(MuesliTheme.textPrimary)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .fill(MuesliTheme.accent.opacity(0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.accent.opacity(0.35), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(isEditingNotes)
    }

    private func templateMenuItem(title: String, systemImage: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark" : systemImage)
                .frame(width: 12)
            Text(title)
        }
    }

    @ViewBuilder
    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(MuesliTheme.textSecondary)
            .padding(.horizontal, MuesliTheme.spacing8)
            .padding(.vertical, 5)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var deleteButton: some View {
        iconButton("trash", label: L10n.text(.sidebarDelete, config: appState.config)) {
            showDeleteConfirmation = true
        }
    }

    @ViewBuilder
    private func templateChip(for snapshot: MeetingTemplateSnapshot) -> some View {
        HStack(spacing: 5) {
            Image(systemName: iconName(for: snapshot))
                .font(.system(size: 10))
            Text(snapshot.name)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(MuesliTheme.accent)
        .padding(.horizontal, MuesliTheme.spacing8)
        .padding(.vertical, 4)
        .background(MuesliTheme.accentSubtle)
        .clipShape(Capsule())
    }

    private var transcriptCTA: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            if hasApiKey {
                Image(systemName: "sparkles")
                    .foregroundStyle(MuesliTheme.accent)
                Text(L10n.text(.meetingTranscriptCallout(action: primarySummaryActionLabel), config: appState.config))
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
            } else {
                Image(systemName: "key.fill")
                    .foregroundStyle(MuesliTheme.accent)
                Text(L10n.text(.meetingAddApiKey, config: appState.config))
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
                Spacer()
                Button(L10n.text(.meetingOpenSettings, config: appState.config)) {
                    controller.openHistoryWindow(tab: .settings)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MuesliTheme.accent)
                .buttonStyle(.plain)
            }
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
    }

    private var hasApiKey: Bool {
        let config = appState.config
        if appState.selectedMeetingSummaryBackend == .chatGPT {
            return appState.isChatGPTAuthenticated
        } else if appState.selectedMeetingSummaryBackend == .openAI {
            return !config.openAIAPIKey.isEmpty || ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil
        } else {
            return !config.openRouterAPIKey.isEmpty || ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] != nil
        }
    }

    private var primarySummaryActionLabel: String {
        guard let meeting else { return L10n.text(.meetingResummarize, config: appState.config) }
        return primarySummaryActionLabel(for: meeting)
    }

    private var copyButtonLabel: String {
        L10n.text(.meetingCopy, config: appState.config)
    }

    private func primarySummaryActionLabel(for meeting: MeetingRecord) -> String {
        hasPendingTemplateChange(for: meeting) ? L10n.text(.meetingApplyTemplate, config: appState.config) : L10n.text(.meetingResummarize, config: appState.config)
    }

    private func activeCopyText(for meeting: MeetingRecord) -> String {
        switch documentMode {
        case .notes:
            return isEditingNotes ? editableNotes : Self.notesContent(for: meeting)
        case .transcript:
            return meeting.rawTranscript
        }
    }

    private func isRawTranscript(_ meeting: MeetingRecord) -> Bool {
        meeting.notesState != .structuredNotes
    }

    private func hasPendingTemplateChange(for meeting: MeetingRecord) -> Bool {
        resolvedPendingTemplateDefinition(for: meeting).id != controller.meetingTemplateSnapshot(for: meeting).id
    }

    private func labelForSelection(on meeting: MeetingRecord, appliedTemplate: MeetingTemplateSnapshot) -> String {
        if pendingTemplateID == appliedTemplate.id {
            return appliedTemplate.name
        }
        return resolvedPendingTemplateDefinition(for: meeting).title
    }

    private func iconName(forSelectionOn meeting: MeetingRecord, appliedTemplate: MeetingTemplateSnapshot) -> String {
        if pendingTemplateID == appliedTemplate.id {
            return iconName(for: appliedTemplate)
        }
        return resolvedPendingTemplateDefinition(for: meeting).icon
    }

    private func iconName(for snapshot: MeetingTemplateSnapshot) -> String {
        switch snapshot.kind {
        case .auto:
            return MeetingTemplates.auto.icon
        case .builtin, .custom:
            return MeetingTemplates.resolveDefinition(
                id: snapshot.id,
                customTemplates: appState.config.customMeetingTemplates
            ).icon
        }
    }

    static func notesContent(for meeting: MeetingRecord) -> String {
        if meeting.notesState != .structuredNotes {
            return "# \(meeting.title)\n\n## Raw Transcript\n\n\(meeting.rawTranscript)"
        }
        return meeting.formattedNotes
    }

    private static func defaultDocumentMode(for meeting: MeetingRecord) -> MeetingDocumentMode {
        meeting.notesState == .structuredNotes ? .notes : .transcript
    }

    private func debounceSaveTitle(meetingID: Int64) {
        titleSaveTask?.cancel()
        let title = editableTitle
        let c = controller
        let item = DispatchWorkItem { c.updateMeetingTitle(id: meetingID, title: title) }
        titleSaveTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private func debounceSaveNotes(meetingID: Int64) {
        notesSaveTask?.cancel()
        let notes = editableNotes
        let c = controller
        let item = DispatchWorkItem { c.updateMeetingNotes(id: meetingID, notes: notes) }
        notesSaveTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private var summaryErrorBinding: Binding<Bool> {
        Binding(
            get: { summaryErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    summaryErrorMessage = nil
                }
            }
        )
    }

    private var calendarAssociationErrorBinding: Binding<Bool> {
        Binding(
            get: { calendarAssociationErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    calendarAssociationErrorMessage = nil
                }
            }
        )
    }

    private func resolvedPendingTemplateDefinition(for meeting: MeetingRecord) -> MeetingTemplateDefinition {
        if let resolved = MeetingTemplates.resolveExactDefinition(
            id: pendingTemplateID,
            customTemplates: appState.config.customMeetingTemplates
        ) {
            return resolved
        }
        return MeetingTemplates.resolveDefinition(
            id: controller.meetingTemplateSnapshot(for: meeting).id,
            customTemplates: appState.config.customMeetingTemplates
        )
    }

    private func calendarEventPickerSheet(for meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
            Text(L10n.text(.meetingSelectCalendarEvent, config: appState.config))
                .font(MuesliTheme.title3())
                .foregroundStyle(MuesliTheme.textPrimary)

            Text(L10n.text(.meetingSelectCalendarEventHint, config: appState.config))
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textSecondary)

            if nearbyCalendarEvents.isEmpty {
                Text(L10n.text(.meetingNoNearbyCalendarEvents, config: appState.config))
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                    .background(MuesliTheme.backgroundRaised)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                        ForEach(nearbyCalendarEvents) { event in
                            Button {
                                do {
                                    try controller.associateMeeting(id: meeting.id, with: event)
                                    if let updated = controller.meeting(id: meeting.id) {
                                        syncLocalState(with: updated)
                                    }
                                    isCalendarEventPickerPresented = false
                                } catch {
                                    calendarAssociationErrorMessage = error.localizedDescription
                                }
                            } label: {
                                HStack(alignment: .center, spacing: MuesliTheme.spacing12) {
                                    Circle()
                                        .fill(calendarEventColor(event))
                                        .frame(width: 10, height: 10)
                                        .overlay(
                                            Circle().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 0.5)
                                        )

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(event.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(MuesliTheme.textPrimary)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        Text(calendarEventMeta(event))
                                            .font(.system(size: 11))
                                            .foregroundStyle(MuesliTheme.textSecondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }

                                    Text(L10n.text(.meetingUseThisCalendarEvent, config: appState.config))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(MuesliTheme.accent)
                                }
                                .padding(MuesliTheme.spacing12)
                                .background(MuesliTheme.backgroundRaised)
                                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
                                .overlay(
                                    RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minHeight: 160, maxHeight: 320)
            }

            HStack {
                Spacer()
                Button(L10n.text(.sidebarCancel, config: appState.config)) {
                    isCalendarEventPickerPresented = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(MuesliTheme.textSecondary)
            }
        }
        .padding(24)
        .frame(minWidth: 560)
        .background(MuesliTheme.backgroundBase)
    }

    private func syncPendingTemplateSelectionIfNeeded(for meeting: MeetingRecord?) {
        guard let meeting else { return }
        guard MeetingTemplates.resolveExactDefinition(
            id: pendingTemplateID,
            customTemplates: appState.config.customMeetingTemplates
        ) == nil else {
            return
        }
        pendingTemplateID = controller.meetingTemplateSnapshot(for: meeting).id
    }

    private func syncLocalState(with meeting: MeetingRecord?) {
        editableTitle = meeting?.title ?? ""
        editableNotes = meeting.map { Self.notesContent(for: $0) } ?? ""
        pendingTemplateID = meeting.map { controller.meetingTemplateSnapshot(for: $0).id } ?? controller.defaultMeetingTemplate().id
        documentMode = meeting.map(Self.defaultDocumentMode(for:)) ?? .notes
    }

    private func formatMeta(_ meeting: MeetingRecord) -> String {
        let time = formatTime(meeting.startTime)
        let duration = formatDuration(meeting.durationSeconds)
        return "\(time)  \u{2022}  \(duration)  \u{2022}  \(L10n.text(.meetingWords(count: meeting.wordCount), config: appState.config))"
    }

    private func formatTime(_ raw: String) -> String {
        MeetingDateFormatting.formatMeetingTimestamp(raw)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        if rounded >= 3600 {
            return "\(rounded / 3600)h \((rounded % 3600) / 60)m"
        }
        if rounded >= 60 {
            let m = rounded / 60
            let s = rounded % 60
            return s == 0 ? "\(m)m" : "\(m)m \(s)s"
        }
        return "\(rounded)s"
    }

    private func calendarEventMeta(_ event: UnifiedCalendarEvent) -> String {
        let timeRange = "\(Self.calendarEventTimeFormatter.string(from: event.startDate)) – \(Self.calendarEventTimeFormatter.string(from: event.endDate))"
        if let calendarName = event.calendarName, !calendarName.isEmpty {
            return "\(timeRange)  •  \(calendarName)"
        }
        if let sourceTitle = event.calendarSourceTitle, !sourceTitle.isEmpty {
            return "\(timeRange)  •  \(sourceTitle)"
        }
        return timeRange
    }

    private func calendarEventColor(_ event: UnifiedCalendarEvent) -> Color {
        colorFromHex(event.calendarColorHex) ?? MuesliTheme.accent
    }

    private func colorFromHex(_ hex: String?) -> Color? {
        guard var hex else { return nil }
        hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else {
            return nil
        }
        return Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0,
            opacity: 1
        )
    }

    private static let calendarEventTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm"
        return formatter
    }()
}

private struct MeetingTranscriptView: View {
    let transcript: String

    var body: some View {
        ScrollView {
            Text(transcript)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(MuesliTheme.textPrimary)
                .frame(maxWidth: 860, alignment: .leading)
                .textSelection(.enabled)
                .padding(MuesliTheme.spacing24)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
