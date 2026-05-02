import SwiftUI
import MuesliCore

private enum MeetingDocumentMode: Hashable {
    case notes
    case transcript
}

private enum ManualNotesSaveStatus {
    case saved
    case saving

    func label(config: AppConfig) -> String {
        switch self {
        case .saved: return L10n.text(.meetingManualNotesSaved, config: config)
        case .saving: return L10n.text(.meetingManualNotesSaving, config: config)
        }
    }
}

struct MeetingDetailView: View {
    private let detailColumnWidth: CGFloat = 860

    let meeting: MeetingRecord?
    let controller: MuesliController
    let appState: AppState
    let onBack: (() -> Void)?
    let backLabel: String
    @State private var isSummarizing = false
    @State private var isEditingNotes = false
    @State private var editableTitle: String
    @State private var editableNotes: String
    @State private var editableManualNotes: String
    @State private var loadedMeetingID: Int64?
    @State private var manualNotesSaveStatus: ManualNotesSaveStatus = .saved
    @State private var manualEditorCommand: MarkdownEditorCommand?
    @State private var pendingTemplateID: String
    @State private var documentMode: MeetingDocumentMode
    @State private var titleSaveTask: DispatchWorkItem?
    @State private var notesSaveTask: DispatchWorkItem?
    @State private var manualNotesSaveStatusTask: DispatchWorkItem?
    @State private var summaryErrorMessage: String?
    @State private var calendarAssociationErrorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var isCalendarEventPickerPresented = false
    @State private var nearbyCalendarEvents: [UnifiedCalendarEvent] = []
    @State private var isLoadingNearbyCalendarEvents = false
    @State private var isAssociatedEventExpanded = true
    @State private var showFolderPopover = false
    @State private var showNewFolderPrompt = false
    @State private var newFolderName = ""

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
        _editableManualNotes = State(initialValue: meeting?.manualNotes ?? "")
        _loadedMeetingID = State(initialValue: meeting?.id)
        _pendingTemplateID = State(initialValue: initialTemplateID)
        _documentMode = State(initialValue: meeting.map(Self.defaultDocumentMode(for:)) ?? .notes)
    }

    private func folder(for meeting: MeetingRecord) -> MeetingFolder? {
        guard let folderID = meeting.folderID else { return nil }
        return appState.folders.first(where: { $0.id == folderID })
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
                .onChange(of: meeting.status) { _, _ in
                    syncLocalState(with: meeting)
                }
                .onChange(of: meeting.manualNotes) { _, _ in
                    syncManualNotesState(with: meeting)
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

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: MuesliTheme.spacing24) {
                    titleBlock(for: meeting)
                        .layoutPriority(1)

                    Spacer(minLength: MuesliTheme.spacing16)

                    headerActions(for: meeting, appliedTemplate: appliedTemplate)
                        .fixedSize()
                }

                VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
                    titleBlock(for: meeting)

                    HStack {
                        Spacer(minLength: 0)
                        headerActions(for: meeting, appliedTemplate: appliedTemplate)
                    }
                }
            }

            if !showsManualNotesEditor(for: meeting), isRawTranscript(meeting), documentMode == .notes {
                transcriptCTA
            }
        }
        .frame(maxWidth: detailColumnWidth, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func titleBlock(for meeting: MeetingRecord) -> some View {
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
                    .lineLimit(1)
                folderChip(for: meeting)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func headerActions(for meeting: MeetingRecord, appliedTemplate: MeetingTemplateSnapshot) -> some View {
        if showsManualNotesEditor(for: meeting) {
            HStack(spacing: MuesliTheme.spacing8) {
                if meeting.status == .recording {
                    recordingControlGroup(for: meeting)
                } else if meeting.status == .noteOnly {
                    statusChip(for: meeting)
                    startRecordingButton(for: meeting)
                    if controller.canDeleteMeeting(meeting) {
                        deleteButton
                    }
                } else if controller.canDeleteMeeting(meeting), meeting.status == .failed {
                    statusChip(for: meeting)
                    deleteButton
                } else {
                    statusChip(for: meeting)
                }
            }
        } else {
            VStack(alignment: .trailing, spacing: MuesliTheme.spacing8) {
                HStack(spacing: MuesliTheme.spacing8) {
                    if hasRecordingAction(for: meeting) {
                        recordingAction(for: meeting)
                    }
                    summaryAction(for: meeting)
                    templateMenu(for: meeting, appliedTemplate: appliedTemplate)
                }
            }
        }
    }

    @ViewBuilder
    private func folderChip(for meeting: MeetingRecord) -> some View {
        if currentFolderLabel(for: meeting) != nil {
            Button {
                showFolderPopover.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: currentFolderIconName(for: meeting))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(currentFolderIconColor(for: meeting))
                    Text(currentFolderLabel(for: meeting) ?? "")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .lineLimit(1)
                }
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
            .help(L10n.text(.meetingMoveToFolder, config: appState.config))
            .popover(isPresented: $showFolderPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    folderPopoverRow(
                        icon: "tray",
                        label: L10n.text(.meetingUnfiled, config: appState.config),
                        isActive: meeting.folderID == nil
                    ) {
                        controller.moveMeeting(id: meeting.id, toFolder: nil)
                        showFolderPopover = false
                    }
                    Divider().padding(.vertical, 4)
                    ForEach(appState.folders) { folder in
                        folderPopoverRow(
                            icon: "folder",
                            label: folder.name,
                            color: MeetingFolderColors.color(for: folder, fallback: MuesliTheme.textSecondary),
                            isActive: meeting.folderID == folder.id
                        ) {
                            controller.moveMeeting(id: meeting.id, toFolder: folder.id)
                            showFolderPopover = false
                        }
                    }
                    Divider().padding(.vertical, 4)
                    folderPopoverRow(
                        icon: "folder.badge.plus",
                        label: L10n.text(.meetingNewFolderEllipsis, config: appState.config)
                    ) {
                        showFolderPopover = false
                        newFolderName = ""
                        showNewFolderPrompt = true
                    }
                }
                .padding(8)
            }
            .alert(L10n.text(.meetingNewFolderTitle, config: appState.config), isPresented: $showNewFolderPrompt) {
                TextField(L10n.text(.sidebarFolderName, config: appState.config), text: $newFolderName)
                Button(L10n.text(.meetingCreate, config: appState.config)) {
                    let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        controller.createFolderAndMoveMeeting(name: trimmed, meetingID: meeting.id)
                    }
                }
                Button(L10n.text(.sidebarCancel, config: appState.config), role: .cancel) {}
            } message: {
                Text(L10n.text(.meetingNewFolderMessage, config: appState.config))
            }
        }
    }

    @ViewBuilder
    private func content(for meeting: MeetingRecord) -> some View {
        if showsManualNotesEditor(for: meeting) {
            let isManualNotesEditable = canEditManualNotes(for: meeting)
            VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                eventSnapshotSection(for: meeting)
                manualNotesToolbar(for: meeting)
                    .disabled(!isManualNotesEditable)

                MarkdownRichTextEditor(
                    text: $editableManualNotes,
                    command: $manualEditorCommand,
                    shouldFocus: isManualNotesEditable && meeting.status == .recording,
                    isEditable: isManualNotesEditable,
                    placeholder: L10n.text(.meetingManualNotesPlaceholder, config: appState.config),
                    onTextChange: { notes in
                        guard isManualNotesEditable else { return }
                        saveManualNotes(meetingID: meeting.id, notes: notes)
                    }
                )
                .frame(maxWidth: detailColumnWidth, maxHeight: .infinity, alignment: .topLeading)
                .background(MuesliTheme.backgroundBase)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if isEditingNotes {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                eventSnapshotSection(for: meeting)
                contentToolbar(for: meeting)

                TextEditor(text: $editableNotes)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(MuesliTheme.spacing24)
                    .background(MuesliTheme.backgroundBase)
                    .frame(maxWidth: detailColumnWidth, maxHeight: .infinity, alignment: .topLeading)
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
                eventSnapshotSection(for: meeting)
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
                .frame(maxWidth: detailColumnWidth, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 40)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private func eventSnapshotSection(for meeting: MeetingRecord) -> some View {
        if let snapshot = meeting.calendarEventSnapshot {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
                    Circle()
                        .fill(calendarEventColor(snapshot))
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 0.5)
                        )
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text(.meetingAssociatedEvent, config: appState.config))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MuesliTheme.textTertiary)
                            .textCase(.uppercase)
                        Text(snapshot.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MuesliTheme.textPrimary)
                        Text(calendarEventMeta(snapshot))
                            .font(.system(size: 12))
                            .foregroundStyle(MuesliTheme.textSecondary)
                    }

                    Spacer(minLength: MuesliTheme.spacing12)

                    HStack(spacing: MuesliTheme.spacing8) {
                        if snapshot.attendees.isEmpty == false {
                            collapseAssociatedEventButton
                        }

                        if let meetingURL = snapshot.meetingURL,
                           let url = URL(string: meetingURL) {
                            Link(destination: url) {
                                HStack(spacing: 6) {
                                    Image(systemName: "video")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(L10n.text(.meetingOpenJoinLink, config: appState.config))
                                        .font(.system(size: 11, weight: .semibold))
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
                    }
                }

                if isAssociatedEventExpanded && !snapshot.attendees.isEmpty {
                    Divider()
                        .background(MuesliTheme.surfaceBorder)

                    VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                        Text(L10n.text(.meetingAttendees, config: appState.config))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MuesliTheme.textSecondary)

                        ForEach(sortedAttendees(snapshot.attendees)) { attendee in
                            HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(attendeeDisplayName(attendee))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(MuesliTheme.textPrimary)

                                    if let email = attendee.email,
                                       !email.isEmpty,
                                       email.caseInsensitiveCompare(attendeeDisplayName(attendee)) != .orderedSame {
                                        Text(email)
                                            .font(.system(size: 11))
                                            .foregroundStyle(MuesliTheme.textTertiary)
                                    }
                                }

                                Spacer(minLength: MuesliTheme.spacing8)

                                HStack(spacing: 6) {
                                    attendeeStatusChip(attendee)
                                    if attendee.isOrganizer {
                                        attendeeMetaChip(
                                            L10n.text(.meetingAttendeeOrganizer, config: appState.config),
                                            tint: MuesliTheme.accent
                                        )
                                    }
                                    if attendee.isCurrentUser {
                                        attendeeMetaChip(
                                            L10n.text(.meetingAttendeeYou, config: appState.config),
                                            tint: MuesliTheme.success
                                        )
                                    }
                                    if attendee.isOptional {
                                        attendeeMetaChip(
                                            L10n.text(.meetingAttendeeOptional, config: appState.config),
                                            tint: MuesliTheme.textTertiary
                                        )
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(MuesliTheme.spacing24)
            .frame(maxWidth: detailColumnWidth, alignment: .leading)
            .background(MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        } else {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                Text(L10n.text(.meetingAssociatedEvent, config: appState.config))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .textCase(.uppercase)

                HStack(alignment: .center, spacing: MuesliTheme.spacing12) {
                    Text(L10n.text(.meetingSelectCalendarEventHint, config: appState.config))
                        .font(MuesliTheme.body())
                        .foregroundStyle(MuesliTheme.textSecondary)

                    Spacer(minLength: MuesliTheme.spacing12)

                    calendarAssociationControl(for: meeting)
                }
            }
            .padding(MuesliTheme.spacing24)
            .frame(maxWidth: detailColumnWidth, alignment: .leading)
            .background(MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
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

    private func showsManualNotesEditor(for meeting: MeetingRecord) -> Bool {
        switch meeting.status {
        case .recording, .processing, .noteOnly, .failed:
            return true
        case .completed:
            return false
        }
    }

    private func canEditManualNotes(for meeting: MeetingRecord) -> Bool {
        meeting.status == .recording || meeting.status == .noteOnly || meeting.status == .failed
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
            compactIconButton("sparkles", label: primarySummaryActionLabel(for: meeting)) {
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
        Button {
            presentCalendarAssociationPicker(for: meeting)
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
    }

    private func presentCalendarAssociationPicker(for meeting: MeetingRecord) {
        nearbyCalendarEvents = []
        isLoadingNearbyCalendarEvents = true

        Task {
            let events = await controller.suggestedCalendarEvents(for: meeting)
            guard loadedMeetingID == meeting.id else { return }
            nearbyCalendarEvents = events
            isLoadingNearbyCalendarEvents = false
        }
    }

    @ViewBuilder
    private func recordingAction(for meeting: MeetingRecord) -> some View {
        if let savedRecordingPath = meeting.savedRecordingPath {
            compactIconButton("folder", label: L10n.text(.meetingShowRecording, config: appState.config)) {
                controller.revealMeetingRecordingInFinder(path: savedRecordingPath)
            }
        }
    }

    private func hasRecordingAction(for meeting: MeetingRecord) -> Bool {
        meeting.savedRecordingPath != nil
    }

    @ViewBuilder
    private func templateMenu(for meeting: MeetingRecord, appliedTemplate: MeetingTemplateSnapshot) -> some View {
        let autoTarget = controller.effectiveAutoMeetingTemplate()
        let autoTitle = autoTarget.id == MeetingTemplates.autoID
            ? MeetingTemplates.auto.title
            : "\(MeetingTemplates.auto.title) (\(autoTarget.title))"
        Menu {
            Button {
                pendingTemplateID = MeetingTemplates.autoID
            } label: {
                templateMenuItem(
                    title: autoTitle,
                    systemImage: MeetingTemplates.auto.icon,
                    isSelected: pendingTemplateID == MeetingTemplates.autoID
                )
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

            if !controller.visibleBuiltInMeetingTemplates().isEmpty {
                Section(L10n.text(.meetingBuiltInTemplates, config: appState.config)) {
                    ForEach(controller.visibleBuiltInMeetingTemplates()) { template in
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
            }

            Divider()

            Button(L10n.text(.meetingManageTemplates, config: appState.config)) {
                controller.showMeetingTemplatesManager()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: iconName(forSelectionOn: meeting, appliedTemplate: appliedTemplate))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
                Text(labelForSelection(on: meeting, appliedTemplate: appliedTemplate))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
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
    private func folderPopoverRow(
        icon: String,
        label: String,
        color: Color = MuesliTheme.textSecondary,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(color)
                    .frame(width: 16)
                Text(label)
                    .font(MuesliTheme.callout())
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MuesliTheme.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func contentToolbar(for meeting: MeetingRecord) -> some View {
        HStack {
            documentModePicker

            Spacer()

            editButton(for: meeting)

            if controller.canDeleteMeeting(meeting) {
                deleteButton
            }

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
        .frame(maxWidth: detailColumnWidth, alignment: .leading)
    }

    @ViewBuilder
    private func manualNotesToolbar(for meeting: MeetingRecord) -> some View {
        HStack(spacing: MuesliTheme.spacing8) {
            if canEditManualNotes(for: meeting) {
                Text(manualNotesSaveStatus.label(config: appState.config))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }

            Spacer()

            markdownToolbarButton(systemImage: "textformat.size", label: L10n.text(.meetingManualToolbarHeading, config: appState.config)) {
                manualEditorCommand = MarkdownEditorCommand(kind: .heading)
            }
            markdownToolbarButton(systemImage: "bold", label: L10n.text(.meetingManualToolbarBold, config: appState.config)) {
                manualEditorCommand = MarkdownEditorCommand(kind: .bold)
            }
            markdownToolbarButton(systemImage: "list.bullet", label: L10n.text(.meetingManualToolbarBullet, config: appState.config)) {
                manualEditorCommand = MarkdownEditorCommand(kind: .bullet)
            }
            markdownToolbarButton(systemImage: "checklist", label: L10n.text(.meetingManualToolbarCheckbox, config: appState.config)) {
                manualEditorCommand = MarkdownEditorCommand(kind: .checkbox)
            }
        }
        .frame(maxWidth: detailColumnWidth, alignment: .leading)
    }

    @ViewBuilder
    private func statusChip(for meeting: MeetingRecord) -> some View {
        let isPaused = meeting.status == .recording && appState.isMeetingRecordingPaused
        let label = isPaused ? "Paused" : meeting.status.displayLabel
        let color = isPaused ? MuesliTheme.transcribing : meeting.status.displayColor
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuesliTheme.textSecondary)
        }
        .padding(.horizontal, MuesliTheme.spacing8)
        .padding(.vertical, 6)
        .background(MuesliTheme.surfacePrimary)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func recordingControlGroup(for meeting: MeetingRecord) -> some View {
        if meeting.status == .recording {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: MuesliTheme.spacing8) {
                    statusChip(for: meeting)
                    pauseResumeRecordingButton
                    stopRecordingButton
                    discardRecordingButton
                }
                .recordingControlsBackground()

                VStack(alignment: .trailing, spacing: MuesliTheme.spacing8) {
                    statusChip(for: meeting)
                    HStack(spacing: MuesliTheme.spacing8) {
                        pauseResumeRecordingButton
                        stopRecordingButton
                        discardRecordingButton
                    }
                    .recordingControlsBackground()
                }
            }
        } else if controller.canDeleteMeeting(meeting), meeting.status == .noteOnly || meeting.status == .failed {
            HStack(spacing: MuesliTheme.spacing8) {
                statusChip(for: meeting)
                deleteButton
            }
        } else {
            statusChip(for: meeting)
        }
    }

    @ViewBuilder
    private func markdownToolbarButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(MuesliTheme.textSecondary)
            .frame(width: 34, height: 30)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(label)
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

    @ViewBuilder
    private func compactIconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MuesliTheme.textSecondary)
                .frame(width: 30, height: 28)
                .background(MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private var deleteButton: some View {
        iconButton("trash", label: L10n.text(.sidebarDelete, config: appState.config)) {
            showDeleteConfirmation = true
        }
    }

    private var pauseResumeRecordingButton: some View {
        let isPaused = appState.isMeetingRecordingPaused
        return Button {
            controller.toggleMeetingRecordingPause()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(isPaused ? "Resume" : "Pause")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isPaused ? MuesliTheme.backgroundBase : MuesliTheme.textPrimary)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 7)
            .background(isPaused ? MuesliTheme.accent : MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(isPaused ? MuesliTheme.accent.opacity(0.35) : MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!appState.isMeetingRecording)
        .help(isPaused ? "Resume recording" : "Pause recording")
    }

    private var stopRecordingButton: some View {
        Button {
            if let meeting {
                flushTitleSave(meetingID: meeting.id)
            }
            controller.stopMeetingRecording()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(L10n.text(.meetingStopRecording, config: appState.config))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 7)
            .background(MuesliTheme.recording)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        }
        .buttonStyle(.plain)
        .help(L10n.text(.meetingStopRecordingHelp, config: appState.config))
    }

    private func startRecordingButton(for meeting: MeetingRecord) -> some View {
        Button {
            flushTitleSave(meetingID: meeting.id)
            controller.startRecordingForExistingMeeting(id: meeting.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "record.circle")
                    .font(.system(size: 10, weight: .semibold))
                Text(L10n.text(.meetingStartRecording, config: appState.config))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 8)
            .background(MuesliTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        }
        .buttonStyle(.plain)
        .help(L10n.text(.meetingStartRecordingHelp, config: appState.config))
    }

    private var discardRecordingButton: some View {
        iconButton("xmark", label: L10n.text(.meetingDiscard, config: appState.config)) {
            controller.discardMeetingWithConfirmation()
        }
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
        if pendingTemplateID == MeetingTemplates.autoID {
            let autoTarget = controller.effectiveAutoMeetingTemplate()
            return autoTarget.id == MeetingTemplates.autoID
                ? MeetingTemplates.auto.title
                : "\(MeetingTemplates.auto.title) (\(autoTarget.title))"
        }
        if pendingTemplateID == appliedTemplate.id {
            return appliedTemplate.name
        }
        return resolvedPendingTemplateDefinition(for: meeting).title
    }

    private func iconName(forSelectionOn meeting: MeetingRecord, appliedTemplate: MeetingTemplateSnapshot) -> String {
        if pendingTemplateID == MeetingTemplates.autoID {
            return MeetingTemplates.auto.icon
        }
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
        if meeting.status == .noteOnly {
            return meeting.manualNotes
        }
        if meeting.notesState != .structuredNotes {
            return "# \(meeting.title)\n\n## Raw Transcript\n\n\(meeting.rawTranscript)"
        }
        return meeting.formattedNotes
    }

    private static func defaultDocumentMode(for meeting: MeetingRecord) -> MeetingDocumentMode {
        if meeting.status == .noteOnly || meeting.status == .recording || meeting.status == .processing || meeting.status == .failed {
            return .notes
        }
        return meeting.notesState == .structuredNotes
            ? MeetingDocumentMode.notes
            : MeetingDocumentMode.transcript
    }

    private func debounceSaveTitle(meetingID: Int64) {
        titleSaveTask?.cancel()
        let title = editableTitle
        let c = controller
        c.cacheMeetingTitle(id: meetingID, title: title)
        let item = DispatchWorkItem { c.updateMeetingTitle(id: meetingID, title: title) }
        titleSaveTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private func flushTitleSave(meetingID: Int64) {
        titleSaveTask?.cancel()
        titleSaveTask = nil
        controller.updateMeetingTitle(id: meetingID, title: editableTitle)
    }

    private func debounceSaveNotes(meetingID: Int64) {
        notesSaveTask?.cancel()
        let notes = editableNotes
        let c = controller
        let item = DispatchWorkItem { c.updateMeetingNotes(id: meetingID, notes: notes) }
        notesSaveTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private func saveManualNotes(meetingID: Int64, notes: String) {
        manualNotesSaveStatus = .saving
        controller.cacheMeetingManualNotes(id: meetingID, notes: notes)
        scheduleManualNotesSaveStatusCheck(meetingID: meetingID, notes: notes)
    }

    private func scheduleManualNotesSaveStatusCheck(meetingID: Int64, notes: String) {
        manualNotesSaveStatusTask?.cancel()
        let item = DispatchWorkItem {
            guard loadedMeetingID == meetingID else { return }
            guard editableManualNotes == notes else { return }
            if controller.hasPersistedMeetingManualNotes(id: meetingID, notes: notes) {
                manualNotesSaveStatus = .saved
            }
        }
        manualNotesSaveStatusTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: item)
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
        ), pendingTemplateID != MeetingTemplates.autoID {
            return resolved
        }
        return MeetingTemplates.resolveDefinition(
            id: pendingTemplateID == MeetingTemplates.autoID
                ? pendingTemplateID
                : controller.meetingTemplateSnapshot(for: meeting).id,
            customTemplates: appState.config.customMeetingTemplates,
            autoTemplateTargetID: appState.config.autoTemplateTargetID
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

            if isLoadingNearbyCalendarEvents {
                VStack {
                    ProgressView()
                        .controlSize(.regular)
                }
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                .background(MuesliTheme.backgroundRaised)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
            } else if nearbyCalendarEvents.isEmpty {
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
        let previousMeetingID = loadedMeetingID
        loadedMeetingID = meeting?.id
        editableTitle = meeting?.title ?? ""
        editableNotes = meeting.map { Self.notesContent(for: $0) } ?? ""
        if previousMeetingID != meeting?.id {
            editableManualNotes = meeting?.manualNotes ?? ""
            manualNotesSaveStatus = .saved
            isAssociatedEventExpanded = true
        } else {
            syncManualNotesState(with: meeting)
        }
        pendingTemplateID = meeting.map { controller.meetingTemplateSnapshot(for: $0).id } ?? controller.defaultMeetingTemplate().id
        documentMode = meeting.map(Self.defaultDocumentMode(for:)) ?? .notes
    }

    private func syncManualNotesState(with meeting: MeetingRecord?) {
        let persistedManualNotes = meeting?.manualNotes ?? ""
        if manualNotesSaveStatus == .saving, editableManualNotes != persistedManualNotes {
            return
        }
        editableManualNotes = persistedManualNotes
        manualNotesSaveStatus = .saved
    }

    private func formatMeta(_ meeting: MeetingRecord) -> String {
        let time = formatCompactTime(meeting.startTime)
        let duration = formatDuration(meeting.durationSeconds)
        return "\(time)  \u{2022}  \(duration)  \u{2022}  \(L10n.text(.meetingWords(count: meeting.wordCount), config: appState.config))"
    }

    private func currentFolderLabel(for meeting: MeetingRecord) -> String? {
        if let folder = folder(for: meeting) {
            return appState.folderPath(for: folder.id)
        }
        if !appState.folders.isEmpty {
            return L10n.text(.meetingUnfiled, config: appState.config)
        }
        return nil
    }

    private func currentFolderIconName(for meeting: MeetingRecord) -> String {
        if let folder = folder(for: meeting) {
            return MeetingFolderIcons.resolvedIconName(for: folder)
        }
        return "folder.badge.plus"
    }

    private func currentFolderIconColor(for meeting: MeetingRecord) -> Color {
        if let folder = folder(for: meeting) {
            return MeetingFolderColors.color(for: folder, fallback: MuesliTheme.accent.opacity(0.8))
        }
        return MuesliTheme.textTertiary
    }

    private func formatTime(_ raw: String) -> String {
        MeetingDateFormatting.formatMeetingTimestamp(raw)
    }

    private func formatCompactTime(_ raw: String) -> String {
        MeetingDateFormatting.formatCompactMeetingTimestamp(raw)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        if rounded >= 3600 {
            return "\(rounded / 3600)h \((rounded % 3600) / 60)m"
        }
        if rounded >= 300 {
            return "\(rounded / 60)m"
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

    private func calendarEventMeta(_ snapshot: MeetingCalendarEventSnapshot) -> String {
        let timeRange = calendarEventTimeRange(start: snapshot.startTime, end: snapshot.endTime)
        if let calendarName = snapshot.calendarName, !calendarName.isEmpty {
            return "\(timeRange)  •  \(calendarName)"
        }
        if let sourceTitle = snapshot.calendarSourceTitle, !sourceTitle.isEmpty {
            return "\(timeRange)  •  \(sourceTitle)"
        }
        return timeRange
    }

    private func calendarEventColor(_ event: UnifiedCalendarEvent) -> Color {
        colorFromHex(event.calendarColorHex) ?? MuesliTheme.accent
    }

    private func calendarEventColor(_ snapshot: MeetingCalendarEventSnapshot) -> Color {
        colorFromHex(snapshot.calendarColorHex) ?? MuesliTheme.accent
    }

    private func calendarEventTimeRange(start: String, end: String) -> String {
        guard let startDate = Self.snapshotDate(from: start),
              let endDate = Self.snapshotDate(from: end) else {
            return "\(start) – \(end)"
        }
        return "\(Self.calendarEventTimeFormatter.string(from: startDate)) – \(Self.calendarEventTimeFormatter.string(from: endDate))"
    }

    private func sortedAttendees(_ attendees: [MeetingCalendarEventAttendee]) -> [MeetingCalendarEventAttendee] {
        attendees.sorted { lhs, rhs in
            if lhs.isCurrentUser != rhs.isCurrentUser {
                return lhs.isCurrentUser && !rhs.isCurrentUser
            }
            if lhs.isOrganizer != rhs.isOrganizer {
                return lhs.isOrganizer && !rhs.isOrganizer
            }
            return attendeeDisplayName(lhs).localizedCaseInsensitiveCompare(attendeeDisplayName(rhs)) == .orderedAscending
        }
    }

    private func attendeeDisplayName(_ attendee: MeetingCalendarEventAttendee) -> String {
        if let name = attendee.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let email = attendee.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            return email
        }
        return "Unknown attendee"
    }

    private func attendeeStatusLabel(_ status: MeetingCalendarEventAttendee.ResponseStatus) -> String {
        switch status {
        case .accepted:
            return L10n.text(.meetingAttendeeAccepted, config: appState.config)
        case .declined:
            return L10n.text(.meetingAttendeeDeclined, config: appState.config)
        case .tentative:
            return L10n.text(.meetingAttendeeTentative, config: appState.config)
        case .pending:
            return L10n.text(.meetingAttendeePending, config: appState.config)
        case .delegated:
            return L10n.text(.meetingAttendeeDelegated, config: appState.config)
        case .completed:
            return L10n.text(.meetingAttendeeCompleted, config: appState.config)
        case .inProcess:
            return L10n.text(.meetingAttendeeInProcess, config: appState.config)
        case .unknown:
            return L10n.text(.meetingAttendeeUnknown, config: appState.config)
        }
    }

    private func attendeeStatusTint(_ status: MeetingCalendarEventAttendee.ResponseStatus) -> Color {
        switch status {
        case .accepted:
            return MuesliTheme.success
        case .declined:
            return MuesliTheme.recording
        case .tentative:
            return MuesliTheme.transcribing
        case .pending, .unknown:
            return MuesliTheme.textTertiary
        case .delegated, .completed, .inProcess:
            return MuesliTheme.accent
        }
    }

    private static func snapshotDate(from raw: String) -> Date? {
        snapshotDateFormatter.date(from: raw) ?? snapshotDateFormatterNoFractional.date(from: raw)
    }

    private func attendeeStatusChip(_ attendee: MeetingCalendarEventAttendee) -> some View {
        attendeeMetaChip(
            attendeeStatusLabel(attendee.responseStatus),
            tint: attendeeStatusTint(attendee.responseStatus)
        )
    }

    private func attendeeMetaChip(_ label: String, tint: Color) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
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

    private var collapseAssociatedEventButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isAssociatedEventExpanded.toggle()
            }
        } label: {
            Image(systemName: isAssociatedEventExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MuesliTheme.textSecondary)
                .frame(width: 28, height: 28)
                .background(MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(
            L10n.text(
                isAssociatedEventExpanded ? .meetingsCollapseComingUp : .meetingsExpandComingUp,
                config: appState.config
            )
        )
    }

    private static let calendarEventTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm"
        return formatter
    }()

    private static let snapshotDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let snapshotDateFormatterNoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private extension View {
    func recordingControlsBackground() -> some View {
        padding(5)
            .background(MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
    }
}

private struct MeetingTranscriptView: View {
    let transcript: String

    var body: some View {
        ScrollView {
            Text(transcript)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(MuesliTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(MuesliTheme.spacing24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
