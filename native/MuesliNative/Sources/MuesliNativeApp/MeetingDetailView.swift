import SwiftUI
import MuesliCore
import MuesliMeetingChat

private enum MeetingDocumentMode: Hashable {
    case notes
    case transcript
}

enum MeetingDetailHeaderLayout {
    case horizontalHeader
    case stackedHeader
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
    private let minimumTranscriptPanelHeight: CGFloat = 160
    private let defaultTranscriptPanelHeight: CGFloat = 240
    private let maximumTranscriptPanelHeight: CGFloat = 560

    let meeting: MeetingRecord?
    let controller: MuesliController
    let appState: AppState
    let onBack: (() -> Void)?
    let backLabel: String
    @State private var isSummarizing = false
    @State private var isRetranscribing = false
    @State private var isEditingNotes = false
    @State private var isEditingTranscript = false
    @State private var editableTitle: String
    @State private var editableNotes: String
    @State private var editableTranscript: String
    @State private var editableManualNotes: String
    @State private var loadedMeetingID: Int64?
    @State private var manualNotesSaveStatus: ManualNotesSaveStatus = .saved
    @State private var manualEditorCommand: MarkdownEditorCommand?
    @State private var pendingTemplateID: String
    @State private var documentMode: MeetingDocumentMode
    @State private var titleSaveTask: DispatchWorkItem?
    @State private var notesSaveTask: DispatchWorkItem?
    @State private var transcriptSaveTask: DispatchWorkItem?
    @State private var manualNotesSaveStatusTask: DispatchWorkItem?
    @State private var summaryErrorMessage: String?
    @State private var calendarAssociationErrorMessage: String?
    @State private var retranscriptionErrorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var isCalendarEventPickerPresented = false
    @State private var nearbyCalendarEvents: [UnifiedCalendarEvent] = []
    @State private var isLoadingNearbyCalendarEvents = false
    @State private var isAssociatedEventExpanded = false
    @State private var showFolderPopover = false
    @State private var showNewFolderPrompt = false
    @State private var newFolderName = ""
    @State private var isLiveTranscriptExpanded = false
    @State private var liveTranscriptPanelHeight: CGFloat = 240
    @State private var liveTranscriptResizeStartHeight: CGFloat?
    @State private var liveChatDraft = ""
    @State private var isMergeSheetPresented = false
    @State private var selectedMergeCandidateIDs = Set<Int64>()
    @State private var mergeErrorMessage: String?
    @State private var isMerging = false
    @State private var transcriptResummaryPromptMeetingID: Int64?
    @State private var transcriptEditOriginalTranscript: String?
    @State private var transcriptEditHadStructuredNotes = false

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
        _editableTranscript = State(initialValue: meeting?.rawTranscript ?? "")
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
        .alert("Couldn't Re-transcribe Meeting", isPresented: retranscriptionErrorBinding) {
            Button("OK", role: .cancel) {
                retranscriptionErrorMessage = nil
            }
        } message: {
            Text(retranscriptionErrorMessage ?? "The saved recording could not be re-transcribed.")
        }
        .alert("Re-summarize Notes?", isPresented: transcriptResummaryPromptBinding) {
            Button("Re-summarize") {
                resummarizeAfterTranscriptEdit()
            }
            Button("Not Now", role: .cancel) {
                transcriptResummaryPromptMeetingID = nil
            }
        } message: {
            Text("Your transcript edits may change the generated notes. Re-summarize now to update them from the edited transcript.")
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
        .sheet(isPresented: $isMergeSheetPresented) {
            if let meeting {
                mergeCandidatesSheet(for: meeting)
            }
        }
        .alert(L10n.text(.meetingMergeFailedTitle, config: appState.config), isPresented: mergeErrorBinding) {
            Button(L10n.text(.commonOK, config: appState.config), role: .cancel) {
                mergeErrorMessage = nil
            }
        } message: {
            Text(mergeErrorMessage ?? "")
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

                    VStack(alignment: .trailing, spacing: MuesliTheme.spacing8) {
                        headerActions(for: meeting, appliedTemplate: appliedTemplate)
                    }
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

            if let savedRecordingPath = resolvedSavedRecordingPath(for: meeting) {
                completedAudioSection(for: meeting, recordingPath: savedRecordingPath)
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
    private func headerActions(for meeting: MeetingRecord, appliedTemplate _: MeetingTemplateSnapshot) -> some View {
        if showsManualNotesEditor(for: meeting) {
            HStack(spacing: MuesliTheme.spacing8) {
                if meeting.status == .recording {
                    recordingControlGroup(for: meeting)
                } else if meeting.status == .noteOnly {
                    statusChip(for: meeting)
                    startRecordingButton(for: meeting)
                    mergeButton(for: meeting)
                    if controller.canDeleteMeeting(meeting) {
                        deleteButton
                    }
                } else if controller.canDeleteMeeting(meeting), meeting.status == .failed {
                    statusChip(for: meeting)
                    mergeButton(for: meeting)
                    deleteButton
                } else {
                    statusChip(for: meeting)
                }
            }
        } else {
            HStack(spacing: MuesliTheme.spacing8) {
                statusChip(for: meeting)
                if Self.showsCompletedOverflowActions(
                    for: meeting,
                    canDelete: controller.canDeleteMeeting(meeting),
                    canMerge: canMergeMeeting(meeting)
                ) {
                    moreActionsMenu(for: meeting)
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
                mergedSourceSection(for: meeting)
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
                liveMeetingComposer(for: meeting)
            }
            .padding(.horizontal, 40)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if isEditingNotes {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                eventSnapshotSection(for: meeting)
                mergedSourceSection(for: meeting)
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
                liveMeetingComposer(for: meeting)
            }
            .padding(.horizontal, 40)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if isEditingTranscript {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                eventSnapshotSection(for: meeting)
                mergedSourceSection(for: meeting)
                contentToolbar(for: meeting)

                TextEditor(text: $editableTranscript)
                    .font(.system(size: 14))
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(MuesliTheme.spacing24)
                    .background(MuesliTheme.backgroundBase)
                    .frame(maxWidth: 980, maxHeight: .infinity, alignment: .topLeading)
                    .onChange(of: editableTranscript) { _, _ in
                        debounceSaveTranscript(meetingID: meeting.id)
                    }
            }
            .padding(.horizontal, 40)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            VStack(alignment: .center, spacing: MuesliTheme.spacing12) {
                eventSnapshotSection(for: meeting)
                mergedSourceSection(for: meeting)
                contentToolbar(for: meeting)

                if Self.usesCompletedDocumentToolbar(for: meeting), isRawTranscript(meeting), documentMode == .notes {
                    transcriptCTA
                }

                ZStack(alignment: .topLeading) {
                    MeetingNotesView(markdown: Self.notesContent(for: meeting))
                        .opacity(documentMode == .notes ? 1 : 0)
                        .allowsHitTesting(documentMode == .notes)
                        .accessibilityHidden(documentMode != .notes)

                    MeetingTranscriptView(transcript: meeting.rawTranscript)
                        .opacity(documentMode == .transcript ? 1 : 0)
                        .allowsHitTesting(documentMode == .transcript)
                        .accessibilityHidden(documentMode != .transcript)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if MeetingChatMountPolicy.showsMeetingChat(for: meeting) {
                    MeetingChatPanel(
                        scope: .meeting(meeting.id),
                        meetings: [meeting],
                        folders: appState.folders,
                        config: appState.config,
                        isChatGPTAuthenticated: appState.isChatGPTAuthenticated,
                        chatStore: appState.meetingChatStore,
                        placeholder: L10n.text(.meetingChatPlaceholderMeeting, config: appState.config),
                        onOpenMeeting: { id in controller.showMeetingDocument(id: id) }
                    )
                }
            }
            .frame(maxWidth: 1080, maxHeight: .infinity, alignment: .topLeading)
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

                        if snapshot.attendees.isEmpty == false {
                            collapseAssociatedEventButton
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
            Text("Notes").tag(MeetingDocumentMode.notes)
            Text("Transcript").tag(MeetingDocumentMode.transcript)
        }
        .pickerStyle(.segmented)
        .tint(MuesliTheme.accent)
        .frame(width: 220)
        .disabled(isEditingNotes || isEditingTranscript)
    }

    static func usesCompletedDocumentToolbar(for meeting: MeetingRecord) -> Bool {
        meeting.status == .completed
    }

    static func usesSummaryTemplateSplitControl(for meeting: MeetingRecord) -> Bool {
        usesCompletedDocumentToolbar(for: meeting)
    }

    static func showsCompletedAudioActions(for meeting: MeetingRecord) -> Bool {
        meeting.status == .completed
            && !(meeting.savedRecordingPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    static func showsCompletedOverflowActions(
        for meeting: MeetingRecord,
        canDelete: Bool,
        canMerge: Bool
    ) -> Bool {
        meeting.status == .completed && (canDelete || canMerge)
    }

    static func showsCompletedDocumentOverflowMenu(
        for meeting: MeetingRecord,
        isEditing: Bool
    ) -> Bool {
        usesCompletedDocumentToolbar(for: meeting) && !isEditing
    }

    static func showsDocumentModePicker(
        for meeting: MeetingRecord,
        in _: MeetingDetailHeaderLayout
    ) -> Bool {
        switch meeting.status {
        case .recording, .processing, .noteOnly, .failed:
            return false
        case .completed:
            return true
        }
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

    private func canMergeMeeting(_ meeting: MeetingRecord) -> Bool {
        MuesliController.normalizedCalendarEventID(meeting.calendarEventID) != nil
            && meeting.mergedIntoMeetingID == nil
            && meeting.status != .recording
            && meeting.status != .processing
    }

    private func relatedMeetings(for meeting: MeetingRecord) -> [MeetingMergeCandidateOption] {
        controller.relatedMeetings(for: meeting)
    }

    private func mergeCandidates(for meeting: MeetingRecord) -> [MeetingRecord] {
        controller.mergeCandidates(for: meeting)
    }

    private func mergedSourceMeetings(for meeting: MeetingRecord) -> [MeetingRecord] {
        controller.mergedSourceMeetings(for: meeting.id)
    }

    private func mergeBlockReasonLabel(_ reason: MeetingMergeCandidateBlockReason?) -> String? {
        switch reason {
        case .liveState:
            return L10n.text(.meetingMergeBlockedLiveState, config: appState.config)
        case .none:
            return nil
        }
    }

    @ViewBuilder
    private func mergeButton(for meeting: MeetingRecord) -> some View {
        if canMergeMeeting(meeting) {
            let related = relatedMeetings(for: meeting)
            let candidates = related.filter(\.isMergeable)
            iconButton("arrow.triangle.merge", label: L10n.text(.meetingMerge, config: appState.config)) {
                selectedMergeCandidateIDs = []
                isMergeSheetPresented = true
            }
            .disabled(related.isEmpty)
            .help(
                related.isEmpty
                    ? L10n.text(.meetingMergeNoCandidates, config: appState.config)
                    : (candidates.isEmpty
                        ? L10n.text(.meetingMergeOnlyBlockedCandidates, config: appState.config)
                        : L10n.text(.meetingMergeSelectNotes, config: appState.config))
            )
        }
    }

    private func isPreparingThisMeeting(_ meeting: MeetingRecord) -> Bool {
        meeting.status == .recording
            && appState.isMeetingStarting
            && !appState.isMeetingRecording
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
            Button {
                runPrimarySummaryAction(for: meeting)
            } label: {
                summaryPrimaryActionLabel(for: meeting)
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

    private func runPrimarySummaryAction(for meeting: MeetingRecord) {
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

    private func summaryPrimaryActionLabel(for meeting: MeetingRecord) -> some View {
        HStack(spacing: 6) {
            if isSummarizing {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.text(.meetingSummarizing, config: appState.config))
                    .font(.system(size: 12, weight: .semibold))
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                Text(primarySummaryActionLabel(for: meeting))
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .foregroundStyle(MuesliTheme.textPrimary)
        .padding(.horizontal, MuesliTheme.spacing12)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private func editButton(for meeting: MeetingRecord) -> some View {
        iconButton(
            isEditingNotes || isEditingTranscript ? "checkmark.circle" : "pencil",
            label: editButtonLabel
        ) {
            toggleDocumentEditing(for: meeting)
        }
    }

    private func toggleDocumentEditing(for meeting: MeetingRecord) {
        if isEditingNotes {
            notesSaveTask?.cancel()
            notesSaveTask = nil
            controller.updateMeetingNotes(id: meeting.id, notes: editableNotes)
            isEditingNotes = false
        } else if isEditingTranscript {
            guard !isRetranscribing else { return }
            transcriptSaveTask?.cancel()
            transcriptSaveTask = nil
            let shouldPromptForResummary = Self.shouldPromptForTranscriptResummary(
                hadStructuredNotes: transcriptEditHadStructuredNotes,
                originalTranscript: transcriptEditOriginalTranscript,
                editedTranscript: editableTranscript
            )
            controller.updateMeetingTranscript(id: meeting.id, transcript: editableTranscript)
            isEditingTranscript = false
            transcriptEditOriginalTranscript = nil
            transcriptEditHadStructuredNotes = false
            if shouldPromptForResummary {
                transcriptResummaryPromptMeetingID = meeting.id
            }
        } else if documentMode == .transcript {
            editableTranscript = meeting.rawTranscript
            transcriptEditOriginalTranscript = meeting.rawTranscript
            transcriptEditHadStructuredNotes = meeting.notesState == .structuredNotes
            isEditingTranscript = true
        } else {
            editableNotes = Self.notesContent(for: meeting)
            isEditingNotes = true
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
            .disabled(isRetranscribing && !isEditingNotes && !isEditingTranscript)
        }
    }

    private func hasRecordingAction(for meeting: MeetingRecord) -> Bool {
        meeting.savedRecordingPath != nil
    }

    private func resolvedSavedRecordingPath(for meeting: MeetingRecord) -> String? {
        guard let savedRecordingPath = meeting.savedRecordingPath,
              FileManager.default.fileExists(atPath: savedRecordingPath) else {
            return nil
        }
        return savedRecordingPath
    }

    @ViewBuilder
    private func completedAudioSection(for meeting: MeetingRecord, recordingPath: String) -> some View {
        ViewThatFits(in: .horizontal) {
            MeetingRecordingPlayerView(recordingPath: recordingPath) {
                if Self.showsCompletedAudioActions(for: meeting) {
                    playerAudioAccessory(for: meeting)
                }
            }

            VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                MeetingRecordingPlayerView(recordingPath: recordingPath)

                if Self.showsCompletedAudioActions(for: meeting) {
                    HStack(spacing: MuesliTheme.spacing8) {
                        Spacer(minLength: 0)
                        recordingAction(for: meeting)
                        retranscribeAction(for: meeting)
                    }
                    .frame(maxWidth: detailColumnWidth, alignment: .trailing)
                }
            }
        }
    }

    @ViewBuilder
    private func playerAudioAccessory(for meeting: MeetingRecord) -> some View {
        HStack(spacing: MuesliTheme.spacing8) {
            recordingAction(for: meeting)
            compactRetranscribeAction(for: meeting)
        }
    }

    @ViewBuilder
    private func mergedSourceSection(for meeting: MeetingRecord) -> some View {
        let sources = mergedSourceMeetings(for: meeting)
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                Text(L10n.text(.meetingMergedSourcesSection, config: appState.config))
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)

                VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                    ForEach(sources) { source in
                        HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(MuesliTheme.textPrimary)
                                Text(formatMeta(source))
                                    .font(.system(size: 11))
                                    .foregroundStyle(MuesliTheme.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Button {
                                controller.showMeetingDocument(id: source.id)
                            } label: {
                                Text(L10n.text(.meetingOpenMergedSource, config: appState.config))
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.plain)
                            if let savedRecordingPath = source.savedRecordingPath {
                                compactIconButton("folder", label: L10n.text(.meetingShowRecording, config: appState.config)) {
                                    controller.revealMeetingRecordingInFinder(path: savedRecordingPath)
                                }
                            }
                        }
                        .padding(MuesliTheme.spacing12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                        )
                    }
                }
            }
            .frame(maxWidth: detailColumnWidth, alignment: .leading)
        }
    }

    @ViewBuilder
    private func retranscribeAction(for meeting: MeetingRecord) -> some View {
        if meeting.savedRecordingPath != nil {
            if isRetranscribing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Re-transcribing...")
                        .font(.system(size: 11))
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                .padding(.horizontal, MuesliTheme.spacing8)
            } else {
                iconButton("arrow.clockwise", label: "Re-transcribe") {
                    isRetranscribing = true
                    controller.retranscribe(meeting: meeting) { [meeting] result in
                        isRetranscribing = false
                        switch result {
                        case .success:
                            if let updated = controller.meeting(id: meeting.id) {
                                syncLocalState(with: updated)
                            }
                        case .failure(let error):
                            retranscriptionErrorMessage = error.localizedDescription
                        }
                    }
                }
                .disabled(meeting.status == .recording || meeting.status == .processing || isEditingNotes || isEditingTranscript)
            }
        }
    }

    @ViewBuilder
    private func compactRetranscribeAction(for meeting: MeetingRecord) -> some View {
        if meeting.savedRecordingPath != nil {
            if isRetranscribing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 30, height: 28)
            } else {
                compactIconButton("arrow.clockwise", label: "Re-transcribe") {
                    isRetranscribing = true
                    controller.retranscribe(meeting: meeting) { [meeting] result in
                        isRetranscribing = false
                        switch result {
                        case .success:
                            if let updated = controller.meeting(id: meeting.id) {
                                syncLocalState(with: updated)
                            }
                        case .failure(let error):
                            retranscriptionErrorMessage = error.localizedDescription
                        }
                    }
                }
                .disabled(meeting.status == .recording || meeting.status == .processing || isEditingNotes || isEditingTranscript)
            }
        }
    }

    @ViewBuilder
    private func templateMenu(for meeting: MeetingRecord, appliedTemplate: MeetingTemplateSnapshot) -> some View {
        Menu {
            templateMenuContent(for: meeting, appliedTemplate: appliedTemplate)
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
    private func templateMenuContent(for meeting: MeetingRecord, appliedTemplate _: MeetingTemplateSnapshot) -> some View {
        let autoTarget = controller.effectiveAutoMeetingTemplate()
        let autoTitle = autoTarget.id == MeetingTemplates.autoID
            ? MeetingTemplates.auto.title
            : "\(MeetingTemplates.auto.title) (\(autoTarget.title))"
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
        Group {
            if Self.usesCompletedDocumentToolbar(for: meeting) {
                let appliedTemplate = controller.meetingTemplateSnapshot(for: meeting)
                let isEditingDocument = isEditingNotes || isEditingTranscript
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: MuesliTheme.spacing12) {
                        documentModePicker

                        Spacer(minLength: MuesliTheme.spacing12)

                        HStack(spacing: MuesliTheme.spacing8) {
                            summaryTemplateSplitControl(for: meeting, appliedTemplate: appliedTemplate)
                            if isEditingDocument {
                                editButton(for: meeting)
                                copyButton(for: meeting)
                            } else if Self.showsCompletedDocumentOverflowMenu(for: meeting, isEditing: isEditingDocument) {
                                completedDocumentOverflowMenu(for: meeting)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                        documentModePicker

                        HStack(spacing: MuesliTheme.spacing8) {
                            summaryTemplateSplitControl(for: meeting, appliedTemplate: appliedTemplate)
                            if isEditingDocument {
                                editButton(for: meeting)
                                copyButton(for: meeting)
                            } else if Self.showsCompletedDocumentOverflowMenu(for: meeting, isEditing: isEditingDocument) {
                                completedDocumentOverflowMenu(for: meeting)
                            }
                        }
                    }
                }
            } else {
                HStack {
                    Spacer()

                    editButton(for: meeting)

                    if controller.canDeleteMeeting(meeting) {
                        deleteButton
                    }

                    retranscribeAction(for: meeting)
                    copyButton(for: meeting)
                }
            }
        }
        .frame(maxWidth: detailColumnWidth, alignment: .leading)
    }

    private func mergeCandidatesSheet(for meeting: MeetingRecord) -> some View {
        let related = relatedMeetings(for: meeting)
        let mergeableCount = related.filter(\.isMergeable).count
        return VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
            Text(L10n.text(.meetingMergeSheetTitle, config: appState.config))
                .font(MuesliTheme.title3())
                .foregroundStyle(MuesliTheme.textPrimary)
            Text(L10n.text(.meetingMergeSheetMessage, config: appState.config))
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textSecondary)

            if related.isEmpty {
                Text(L10n.text(.meetingMergeNoCandidates, config: appState.config))
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                if mergeableCount == 0 {
                    Text(L10n.text(.meetingMergeOnlyBlockedCandidates, config: appState.config))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MuesliTheme.textSecondary)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                        ForEach(related) { option in
                            let candidate = option.meeting
                            Button {
                                guard option.isMergeable else { return }
                                if selectedMergeCandidateIDs.contains(candidate.id) {
                                    selectedMergeCandidateIDs.remove(candidate.id)
                                } else {
                                    selectedMergeCandidateIDs.insert(candidate.id)
                                }
                            } label: {
                                HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
                                    Image(systemName: selectedMergeCandidateIDs.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(selectedMergeCandidateIDs.contains(candidate.id) ? MuesliTheme.accent : MuesliTheme.textTertiary)
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(candidate.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(MuesliTheme.textPrimary)
                                        Text(formatMeta(candidate))
                                            .font(.system(size: 11))
                                            .foregroundStyle(MuesliTheme.textSecondary)
                                        if !candidate.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            Text(candidate.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines))
                                                .font(.system(size: 11))
                                                .foregroundStyle(MuesliTheme.textTertiary)
                                                .lineLimit(3)
                                        }
                                        if let blockReason = mergeBlockReasonLabel(option.blockingReason) {
                                            Text(blockReason)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(MuesliTheme.textSecondary)
                                                .lineLimit(3)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(MuesliTheme.spacing12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(MuesliTheme.surfacePrimary)
                                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                                .overlay(
                                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                                )
                                .opacity(option.isMergeable ? 1 : 0.72)
                            }
                            .buttonStyle(.plain)
                            .disabled(!option.isMergeable)
                        }
                    }
                }
            }

            HStack {
                Text(L10n.text(.meetingMergeSelected(count: selectedMergeCandidateIDs.count), config: appState.config))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)

                Spacer()

                Button(L10n.text(.sidebarCancel, config: appState.config)) {
                    isMergeSheetPresented = false
                }
                .buttonStyle(.plain)

                Button(isMerging ? L10n.text(.meetingMergeProcessing, config: appState.config) : L10n.text(.meetingMergeKeepSummary, config: appState.config)) {
                    runMerge(for: meeting, summaryMode: .keepCurrentSummary)
                }
                .buttonStyle(.bordered)
                .disabled(selectedMergeCandidateIDs.isEmpty || isMerging)

                Button(isMerging ? L10n.text(.meetingMergeProcessing, config: appState.config) : L10n.text(.meetingMergeReSummarize, config: appState.config)) {
                    runMerge(for: meeting, summaryMode: .reSummarize)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedMergeCandidateIDs.isEmpty || isMerging)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 420)
        .background(MuesliTheme.backgroundBase)
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

    private func hasTranscriptContent(for meeting: MeetingRecord) -> Bool {
        if meeting.status == .recording || meeting.status == .processing {
            guard appState.config.enableLiveMeetingTranscript else { return false }
            return !liveTranscriptTurns(for: meeting).isEmpty
        }
        return !meeting.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func liveTranscriptTurns(for meeting: MeetingRecord) -> [LiveMeetingTranscriptTurn] {
        guard appState.activeMeetingTranscriptMeetingID == meeting.id else { return [] }
        return appState.activeMeetingTranscriptTurns
    }

    @ViewBuilder
    private func liveMeetingComposer(for meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLiveTranscriptExpanded {
                transcriptPanel(for: meeting)
            }

            HStack(spacing: MuesliTheme.spacing12) {
                Button {
                    if isLiveTranscriptExpanded {
                        isLiveTranscriptExpanded = false
                    } else {
                        liveTranscriptPanelHeight = max(liveTranscriptPanelHeight, defaultTranscriptPanelHeight)
                        isLiveTranscriptExpanded = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isLiveTranscriptExpanded ? "waveform.and.magnifyingglass" : "waveform")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: isLiveTranscriptExpanded ? "chevron.down" : "chevron.up")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .frame(width: 44, height: 34)
                    .background(MuesliTheme.surfacePrimary)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!hasTranscriptContent(for: meeting))
                .help(
                    hasTranscriptContent(for: meeting)
                        ? L10n.text(
                            isLiveTranscriptExpanded ? .meetingLiveTranscriptToggleCollapse : .meetingLiveTranscriptToggleExpand,
                            config: appState.config
                        )
                        : L10n.text(.meetingTranscriptUnavailable, config: appState.config)
                )

                TextField(L10n.text(.meetingLiveChatPlaceholder, config: appState.config), text: $liveChatDraft)
                    .textFieldStyle(.plain)
                    .font(MuesliTheme.body())
                    .padding(.horizontal, MuesliTheme.spacing16)
                    .padding(.vertical, 10)
                    .background(MuesliTheme.backgroundBase)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                    )
            }
            .padding(MuesliTheme.spacing12)
            .frame(maxWidth: detailColumnWidth, alignment: .leading)
            .background(MuesliTheme.backgroundRaised)
        }
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func transcriptPanel(for meeting: MeetingRecord) -> some View {
        if (meeting.status == .recording || meeting.status == .processing) && appState.config.enableLiveMeetingTranscript {
            transcriptPanelContainer {
                LiveMeetingTranscriptView(
                    turns: liveTranscriptTurns(for: meeting),
                    placeholder: L10n.text(.meetingLiveTranscriptPlaceholder, config: appState.config)
                )
            }
        } else if hasTranscriptContent(for: meeting) {
            transcriptPanelContainer {
                MeetingTranscriptView(transcript: meeting.rawTranscript)
            }
        } else {
            Text(L10n.text(.meetingTranscriptUnavailable, config: appState.config))
                .font(.system(size: 12))
                .foregroundStyle(MuesliTheme.textTertiary)
                .padding(MuesliTheme.spacing16)
                .frame(maxWidth: detailColumnWidth, minHeight: 100, alignment: .topLeading)
                .background(MuesliTheme.backgroundRaised)
                .overlay(alignment: .bottom) {
                    Divider()
                        .background(MuesliTheme.surfaceBorder)
                }
        }
    }

    private func transcriptPanelContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            transcriptResizeHandle
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(
            maxWidth: detailColumnWidth,
            minHeight: liveTranscriptPanelHeight,
            maxHeight: liveTranscriptPanelHeight,
            alignment: .topLeading
        )
        .background(MuesliTheme.backgroundRaised)
        .overlay(alignment: .bottom) {
            Divider()
                .background(MuesliTheme.surfaceBorder)
        }
    }

    private var transcriptResizeHandle: some View {
        HStack {
            Spacer()
            Capsule()
                .fill(MuesliTheme.surfaceBorder)
                .frame(width: 42, height: 5)
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 8)
        .background(MuesliTheme.backgroundRaised)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if liveTranscriptResizeStartHeight == nil {
                        liveTranscriptResizeStartHeight = liveTranscriptPanelHeight
                    }
                    let baseHeight = liveTranscriptResizeStartHeight ?? liveTranscriptPanelHeight
                    let proposedHeight = baseHeight - value.translation.height
                    liveTranscriptPanelHeight = clampedTranscriptPanelHeight(proposedHeight)
                }
                .onEnded { _ in
                    liveTranscriptResizeStartHeight = nil
                }
        )
        .help("Drag to resize transcript")
    }

    private func clampedTranscriptPanelHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, minimumTranscriptPanelHeight), maximumTranscriptPanelHeight)
    }

    @ViewBuilder
    private func statusChip(for meeting: MeetingRecord) -> some View {
        let isPreparing = isPreparingThisMeeting(meeting)
        let isPaused = meeting.status == .recording && appState.isMeetingRecordingPaused
        let label = isPreparing ? "Preparing" : isPaused ? "Paused" : meeting.status.displayLabel
        let color = isPreparing || isPaused ? MuesliTheme.transcribing : meeting.status.displayColor
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
            if isPreparingThisMeeting(meeting) {
                meetingPreparationControlGroup(for: meeting)
            } else {
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
    private func meetingPreparationControlGroup(for meeting: MeetingRecord) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MuesliTheme.spacing8) {
                statusChip(for: meeting)
                meetingPreparationStatus
                cancelMeetingPreparationButton
            }
            .recordingControlsBackground()

            VStack(alignment: .trailing, spacing: MuesliTheme.spacing8) {
                statusChip(for: meeting)
                HStack(spacing: MuesliTheme.spacing8) {
                    meetingPreparationStatus
                    cancelMeetingPreparationButton
                }
                .recordingControlsBackground()
            }
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
        Menu {
            Button {
                MeetingExporter.export(meeting: meeting, content: .notes)
            } label: {
                Label(L10n.text(.meetingExportNotes, config: appState.config), systemImage: "doc.text")
            }
            Button {
                MeetingExporter.export(meeting: meeting, content: .transcript)
            } label: {
                Label(L10n.text(.meetingExportTranscript, config: appState.config), systemImage: "text.quote")
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
        .disabled(isEditingNotes || isEditingTranscript)
    }

    @ViewBuilder
    private func moreActionsMenu(for meeting: MeetingRecord) -> some View {
        if Self.showsCompletedOverflowActions(
            for: meeting,
            canDelete: controller.canDeleteMeeting(meeting),
            canMerge: canMergeMeeting(meeting)
        ) {
            Menu {
                if canMergeMeeting(meeting) {
                    Button {
                        selectedMergeCandidateIDs = []
                        isMergeSheetPresented = true
                    } label: {
                        Label(L10n.text(.meetingMerge, config: appState.config), systemImage: "arrow.triangle.merge")
                    }
                }

                if controller.canDeleteMeeting(meeting) {
                    if canMergeMeeting(meeting) {
                        Divider()
                    }
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Meeting", systemImage: "trash")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(MuesliTheme.textSecondary)
                .frame(width: 30, height: 28)
                .background(MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("More actions")
        }
    }

    private func templateMenuItem(title: String, systemImage: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark" : systemImage)
                .frame(width: 12)
            Text(title)
        }
    }

    private func copyButton(for meeting: MeetingRecord) -> some View {
        iconButton("doc.on.doc", label: copyButtonLabel) {
            controller.copyToClipboard(activeCopyText(for: meeting))
        }
    }

    private func compactIconButtonLabel(_ systemImage: String) -> some View {
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

    @ViewBuilder
    private func completedDocumentOverflowMenu(for meeting: MeetingRecord) -> some View {
        Menu {
            Button(editButtonLabel) {
                toggleDocumentEditing(for: meeting)
            }

            Button(copyButtonLabel) {
                controller.copyToClipboard(activeCopyText(for: meeting))
            }
        } label: {
            compactIconButtonLabel("ellipsis")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("More options")
    }

    @ViewBuilder
    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .fixedSize(horizontal: true, vertical: false)
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

    private var meetingPreparationStatus: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 14, height: 14)
                .accessibilityLabel("Preparing transcription")
            Text(appState.meetingStartStatus ?? "Meeting transcription will start shortly.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuesliTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, MuesliTheme.spacing12)
        .padding(.vertical, 7)
        .background(MuesliTheme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private var cancelMeetingPreparationButton: some View {
        iconButton("xmark", label: "Cancel") {
            controller.cancelMeetingPreparation()
        }
        .help("Cancel meeting preparation")
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
                Text(appState.config.resolvedAppLanguage.effectiveLanguageCode == "es" ? "Parar" : "Stop")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 7)
            .background(MuesliTheme.recording)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        }
        .buttonStyle(.plain)
        .disabled(!appState.isMeetingRecording)
        .help(L10n.text(.meetingStopRecordingHelp, config: appState.config))
    }

    private func startRecordingButton(for meeting: MeetingRecord) -> some View {
        Button {
            flushTitleSave(meetingID: meeting.id)
            controller.startRecordingForExistingMeeting(id: meeting.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(L10n.text(.meetingStartRecording, config: appState.config))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(MuesliTheme.backgroundBase)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 7)
            .background(MuesliTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.accent.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(L10n.text(.meetingStartRecordingHelp, config: appState.config))
    }

    private var discardRecordingButton: some View {
        iconButton("xmark", label: L10n.text(.meetingDiscard, config: appState.config)) {
            controller.discardMeetingWithConfirmation()
        }
    }

    private func summaryTemplateSplitControl(
        for meeting: MeetingRecord,
        appliedTemplate: MeetingTemplateSnapshot
    ) -> some View {
        HStack(spacing: 0) {
            Button {
                runPrimarySummaryAction(for: meeting)
            } label: {
                summaryPrimaryActionLabel(for: meeting)
                    .frame(minHeight: 32)
                    .background(MuesliTheme.accent.opacity(0.18))
            }
            .buttonStyle(.plain)
            .disabled(isEditingNotes || isEditingTranscript || isSummarizing)

            Menu {
                templateMenuContent(for: meeting, appliedTemplate: appliedTemplate)
            } label: {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(MuesliTheme.accent.opacity(0.35))
                        .frame(width: 1, height: 18)
                        .frame(height: 18)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .frame(width: 30, height: 32)
                }
                .background(MuesliTheme.accent.opacity(0.18))
            }
            .menuStyle(.borderlessButton)
            .disabled(isEditingNotes || isEditingTranscript || isSummarizing)
        }
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .strokeBorder(MuesliTheme.accent.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
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
        } else if appState.selectedMeetingSummaryBackend == .ollama {
            return true
        } else if appState.selectedMeetingSummaryBackend == .lmStudio {
            return MeetingSummaryClient.lmStudioHasRequiredSettings(config: config)
        } else if appState.selectedMeetingSummaryBackend == .customLLM {
            return MeetingSummaryClient.customLLMHasRequiredSettings(config: config)
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

    private var editButtonLabel: String {
        if isEditingNotes || isEditingTranscript {
            return "Done"
        }
        return documentMode == .transcript ? "Edit Transcript" : "Edit Notes"
    }

    private func primarySummaryActionLabel(for meeting: MeetingRecord) -> String {
        hasPendingTemplateChange(for: meeting) ? L10n.text(.meetingApplyTemplate, config: appState.config) : L10n.text(.meetingResummarize, config: appState.config)
    }

    private func activeCopyText(for meeting: MeetingRecord) -> String {
        switch documentMode {
        case .notes:
            return isEditingNotes ? editableNotes : Self.notesContent(for: meeting)
        case .transcript:
            return isEditingTranscript ? editableTranscript : meeting.rawTranscript
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
        return meeting.notesState == .structuredNotes ? .notes : .transcript
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

    private func debounceSaveTranscript(meetingID: Int64) {
        transcriptSaveTask?.cancel()
        let transcript = editableTranscript
        let c = controller
        let item = DispatchWorkItem { c.updateMeetingTranscript(id: meetingID, transcript: transcript) }
        transcriptSaveTask = item
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

    private var mergeErrorBinding: Binding<Bool> {
        Binding(
            get: { mergeErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    mergeErrorMessage = nil
                }
            }
        )
    }

    private var retranscriptionErrorBinding: Binding<Bool> {
        Binding(
            get: { retranscriptionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    retranscriptionErrorMessage = nil
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

    private var transcriptResummaryPromptBinding: Binding<Bool> {
        Binding(
            get: { transcriptResummaryPromptMeetingID != nil },
            set: { isPresented in
                if !isPresented {
                    transcriptResummaryPromptMeetingID = nil
                }
            }
        )
    }

    private func runMerge(for meeting: MeetingRecord, summaryMode: MeetingMergeSummaryMode) {
        guard !selectedMergeCandidateIDs.isEmpty else { return }
        isMerging = true
        controller.mergeMeetings(
            into: meeting.id,
            sourceMeetingIDs: Array(selectedMergeCandidateIDs).sorted(),
            summaryMode: summaryMode
        ) { result in
            isMerging = false
            switch result {
            case .success:
                selectedMergeCandidateIDs = []
                isMergeSheetPresented = false
            case .failure(let error):
                mergeErrorMessage = error.localizedDescription
            }
        }
    }

    private static func shouldPromptForTranscriptResummary(
        hadStructuredNotes: Bool,
        originalTranscript: String?,
        editedTranscript: String
    ) -> Bool {
        guard hadStructuredNotes, let originalTranscript else { return false }
        return originalTranscript != editedTranscript
    }

    private func resummarizeAfterTranscriptEdit() {
        guard let meetingID = transcriptResummaryPromptMeetingID else { return }
        transcriptResummaryPromptMeetingID = nil
        guard let updatedMeeting = controller.meeting(id: meetingID) else { return }
        isSummarizing = true
        controller.resummarize(meeting: updatedMeeting) { [meetingID] result in
            isSummarizing = false
            switch result {
            case .success:
                if let refreshed = controller.meeting(id: meetingID) {
                    syncLocalState(with: refreshed)
                }
            case .failure(let error):
                summaryErrorMessage = error.localizedDescription
            }
        }
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
        let meetingChanged = previousMeetingID != meeting?.id
        loadedMeetingID = meeting?.id
        editableTitle = meeting?.title ?? ""
        if meetingChanged || !isEditingNotes {
            editableNotes = meeting.map { Self.notesContent(for: $0) } ?? ""
        }
        if meetingChanged || !isEditingTranscript {
            editableTranscript = meeting?.rawTranscript ?? ""
        }
        if meetingChanged {
            editableManualNotes = meeting?.manualNotes ?? ""
            manualNotesSaveStatus = .saved
            isAssociatedEventExpanded = false
            isLiveTranscriptExpanded = false
            liveTranscriptPanelHeight = defaultTranscriptPanelHeight
            liveTranscriptResizeStartHeight = nil
            liveChatDraft = ""
            selectedMergeCandidateIDs = []
            isMerging = false
            mergeErrorMessage = nil
            transcriptResummaryPromptMeetingID = nil
            transcriptEditOriginalTranscript = nil
            transcriptEditHadStructuredNotes = false
        } else {
            syncManualNotesState(with: meeting)
        }
        pendingTemplateID = meeting.map { controller.meetingTemplateSnapshot(for: $0).id } ?? controller.defaultMeetingTemplate().id
        if meetingChanged {
            documentMode = meeting.map(Self.defaultDocumentMode(for:)) ?? .notes
            isEditingNotes = false
            isEditingTranscript = false
            showFolderPopover = false
            showNewFolderPrompt = false
            newFolderName = ""
        }
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

private struct MarqueeTitleTextField: View {
    @Binding var text: String
    let onSubmit: () -> Void
    let onTextChange: () -> Void

    @State private var isHovering = false
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var marqueeOffset: CGFloat = 0
    @State private var marqueeRunID = UUID()
    @FocusState private var isTitleFocused: Bool

    private let titleFont = Font.system(size: 30, weight: .bold)

    var body: some View {
        ZStack(alignment: .leading) {
            TextField("Meeting Title", text: $text)
                .font(titleFont)
                .foregroundStyle(MuesliTheme.textPrimary)
                .textFieldStyle(.plain)
                .lineLimit(1)
                .opacity(shouldShowMarquee ? 0 : 1)
                .focused($isTitleFocused)
                .onSubmit(onSubmit)
                .onChange(of: text) { _, _ in
                    onTextChange()
                    restartMarqueeIfNeeded()
                }
                .onChange(of: isTitleFocused) { _, _ in
                    restartMarqueeIfNeeded()
                }

            Text(text.isEmpty ? "Meeting Title" : text)
                .font(titleFont)
                .fontWeight(.bold)
                .foregroundStyle(MuesliTheme.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: marqueeOffset)
                .opacity(shouldShowMarquee ? 1 : 0)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: TitleContainerWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .overlay(
            Text(text.isEmpty ? "Meeting Title" : text)
                .font(titleFont)
                .fontWeight(.bold)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .hidden()
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: TitleContentWidthPreferenceKey.self, value: proxy.size.width)
                    }
                )
                .allowsHitTesting(false)
        )
        .onTapGesture {
            isTitleFocused = true
        }
        .onPreferenceChange(TitleContainerWidthPreferenceKey.self) { width in
            guard abs(containerWidth - width) > 0.5 else { return }
            containerWidth = width
            restartMarqueeIfNeeded()
        }
        .onPreferenceChange(TitleContentWidthPreferenceKey.self) { width in
            guard abs(contentWidth - width) > 0.5 else { return }
            contentWidth = width
            restartMarqueeIfNeeded()
        }
        .onHover { hovering in
            isHovering = hovering
            restartMarqueeIfNeeded()
        }
    }

    private var overflowDistance: CGFloat {
        max(contentWidth - containerWidth, 0)
    }

    private var shouldShowMarquee: Bool {
        containerWidth > 0 && isHovering && !isTitleFocused && overflowDistance > 24
    }

    private func restartMarqueeIfNeeded() {
        guard shouldShowMarquee else {
            if marqueeOffset != 0 {
                let runID = UUID()
                marqueeRunID = runID
                withAnimation(.easeOut(duration: 0.18)) {
                    marqueeOffset = 0
                }
            }
            return
        }

        let runID = UUID()
        marqueeRunID = runID

        marqueeOffset = 0
        let distance = overflowDistance + 28
        let duration = min(max(Double(distance) / 42.0, 3.0), 12.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard marqueeRunID == runID, shouldShowMarquee else { return }
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                marqueeOffset = -distance
            }
        }
    }
}

private struct TitleContainerWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TitleContentWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct TranscriptChatMessage: Identifiable, Equatable {
    let id: Int
    let timestamp: String?
    let speaker: String?
    let text: String

    var isUser: Bool {
        speaker?.localizedCaseInsensitiveCompare("You") == .orderedSame
    }

    static func messages(from transcript: String) -> [TranscriptChatMessage] {
        let normalized = transcript.replacingOccurrences(of: "\r\n", with: "\n")
        let rawLines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var messages: [TranscriptChatMessage] = []
        for rawLine in rawLines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let parsed = parseLine(line, id: messages.count)
            messages.append(parsed)
        }

        return messages
    }

    private static func parseLine(_ line: String, id: Int) -> TranscriptChatMessage {
        if line.hasPrefix("["),
           let timestampEnd = line.firstIndex(of: "]") {
            let timestamp = String(line[line.index(after: line.startIndex)..<timestampEnd])
            let remainderStart = line.index(after: timestampEnd)
            let remainder = line[remainderStart...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let speakerText = splitSpeakerAndText(remainder)
            return TranscriptChatMessage(
                id: id,
                timestamp: timestamp.isEmpty ? nil : timestamp,
                speaker: speakerText.speaker,
                text: speakerText.text
            )
        }

        let speakerText = splitSpeakerAndText(line)
        return TranscriptChatMessage(
            id: id,
            timestamp: nil,
            speaker: speakerText.speaker,
            text: speakerText.text
        )
    }

    private static func splitSpeakerAndText(_ text: String) -> (speaker: String?, text: String) {
        guard let separator = text.firstIndex(of: ":") else {
            return (nil, text)
        }

        let candidate = text[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLikelySpeakerLabel(candidate) else {
            return (nil, text)
        }

        let bodyStart = text.index(after: separator)
        let body = text[bodyStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (candidate, body.isEmpty ? text : body)
    }

    private static func isLikelySpeakerLabel(_ label: String) -> Bool {
        guard !label.isEmpty, label.count <= 32 else { return false }
        if label.localizedCaseInsensitiveCompare("You") == .orderedSame { return true }
        if label.localizedCaseInsensitiveCompare("Others") == .orderedSame { return true }
        if label.range(of: #"^Speaker\s+\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return false
    }
}

private struct MeetingTranscriptView: View {
    let transcript: String
    @State private var messages: [TranscriptChatMessage]

    init(transcript: String) {
        self.transcript = transcript
        _messages = State(initialValue: TranscriptChatMessage.messages(from: transcript))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                if messages.isEmpty {
                    Text("No transcript available")
                        .font(MuesliTheme.body())
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .frame(maxWidth: 860, alignment: .leading)
                        .padding(MuesliTheme.spacing24)
                } else {
                    ForEach(messages) { message in
                        TranscriptChatBubble(message: message)
                    }
                }
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(.horizontal, MuesliTheme.spacing24)
            .padding(.vertical, MuesliTheme.spacing16)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onChange(of: transcript) { _, newTranscript in
            messages = TranscriptChatMessage.messages(from: newTranscript)
        }
    }
}

private struct TranscriptChatBubble: View {
    let message: TranscriptChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: MuesliTheme.spacing8) {
            if message.isUser {
                Spacer(minLength: 80)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let metadata = metadata {
                    Text(metadata)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .textSelection(.enabled)
                }
                Text(message.text)
                    .font(.system(size: 14))
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 8)
            .background(message.isUser ? MuesliTheme.accent.opacity(0.18) : MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(message.isUser ? MuesliTheme.accent.opacity(0.25) : MuesliTheme.surfaceBorder, lineWidth: 1)
            )
            .frame(maxWidth: 680, alignment: message.isUser ? .trailing : .leading)

            if !message.isUser {
                Spacer(minLength: 80)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }

    private var metadata: String? {
        switch (message.speaker, message.timestamp) {
        case let (speaker?, timestamp?):
            return "\(speaker) \(timestamp)"
        case let (speaker?, nil):
            return speaker
        case let (nil, timestamp?):
            return timestamp
        case (nil, nil):
            return nil
        }
    }
}

private struct LiveMeetingTranscriptView: View {
    let turns: [LiveMeetingTranscriptTurn]
    let placeholder: String

    var body: some View {
        MeetingTranscriptChatView(
            turns: turns.map { $0.asDisplayTurn() },
            placeholder: placeholder,
            autoScrollToLatest: true
        )
    }
}
