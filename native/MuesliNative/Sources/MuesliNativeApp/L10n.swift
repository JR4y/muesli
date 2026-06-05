import Foundation

enum AppLanguage: String, CaseIterable, Codable {
    case system
    case spanish = "es"
    case english = "en"

    var settingsLabel: String {
        switch self {
        case .system:
            return "System"
        case .spanish:
            return "Espanol"
        case .english:
            return "English"
        }
    }

    static func resolved(_ rawValue: String?) -> AppLanguage {
        guard let rawValue,
              let language = AppLanguage(rawValue: rawValue) else {
            return .system
        }
        return language
    }

    var effectiveLanguageCode: String {
        switch self {
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return preferred.hasPrefix("es") ? "es" : "en"
        case .spanish:
            return "es"
        case .english:
            return "en"
        }
    }
}

enum L10nKey {
    case sidebarUpdateNow
    case sidebarRestart
    case sidebarUpdateAvailable
    case sidebarUpdateReady
    case sidebarUpdateTooltip
    case sidebarRestartTooltip
    case sidebarDictations
    case sidebarMeetings
    case sidebarDictionary
    case sidebarModels
    case sidebarShortcuts
    case sidebarSettings
    case sidebarAbout
    case sidebarDelete
    case sidebarCancel
    case sidebarMeetingsMovedToUnfiled(count: Int)
    case sidebarFolderRemoved
    case sidebarGreeting(name: String)
    case sidebarSearchPlaceholder
    case sidebarNewMeetingFolder
    case sidebarAllMeetings
    case sidebarRename
    case sidebarAddSubfolder
    case sidebarFolderName
    case sidebarNewFolder
    case sidebarFolderColor
    case sidebarFolderNoColor
    case sidebarFolderColorGray
    case sidebarFolderColorBlue
    case sidebarFolderColorGreen
    case sidebarFolderColorAmber
    case sidebarFolderColorOrange
    case sidebarFolderColorYellow
    case sidebarFolderColorRed
    case sidebarFolderColorPurple
    case sidebarFolderColorPink
    case sidebarFolderColorCyan
    case sidebarFolderColorIndigo
    case sidebarFolderColorBrown
    case settingsLanguage
    case meetingsFilterAllTime
    case meetingsFilterLast2Days
    case meetingsFilterLastWeek
    case meetingsFilterLast2Weeks
    case meetingsFilterLastMonth
    case meetingsFilterLast3Months
    case meetingsSortNewestFirst
    case meetingsSortOldestFirst
    case meetingsToday
    case meetingsTomorrow
    case meetingsComingUp
    case meetingsCollapseComingUp
    case meetingsExpandComingUp
    case meetingsCollapsedHint
    case meetingsCalendarSyncHint
    case meetingsJoinAndRecord
    case meetingsPopupUpcomingTitle
    case meetingsPopupStartingNowTitle
    case meetingsPopupStartRecording
    case meetingsPopupJoinOnly
    case meetingsPopupRecordOnly
    case meetingsPopupStartsInMinutes(count: Int)
    case meetingsPopupStartingNow
    case meetingsPopupStartedMinutesAgo(count: Int)
    case meetingsPopupDetectedTitle
    case meetingsPopupTranscriptionCompleteTitle
    case meetingsPopupViewNotes
    case meetingsPopupEndedTitle
    case meetingsPopupScheduledTimeOver
    case meetingsAddToFolder
    case meetingsHideFromComingUp
    case meetingsCount(count: Int)
    case meetingsHeaderHint
    case meetingsManageTemplates
    case meetingsEditFolder
    case meetingsNewSubfolder
    case meetingsFolderEditorTitle
    case meetingsFolderParent
    case meetingsFolderRoot
    case meetingsFolderAppearance
    case meetingsFolderIcon
    case meetingsFolderSave
    case meetingsEmptyTitle
    case meetingsEmptyFolderTitle
    case meetingsEmptyMessage
    case meetingsEmptyFolderMessage
    case meetingDeleteTitle
    case meetingDeleteMessage
    case meetingMoveToFolder
    case meetingUnfiled
    case meetingNewFolderEllipsis
    case meetingNewFolderTitle
    case meetingCreate
    case meetingNewFolderMessage
    case meetingDeleteHelp
    case meetingBackToMeetings
    case meetingAssociateEvent
    case meetingCalendarLinked
    case meetingAssociatedEvent
    case meetingAttendees
    case meetingOpenJoinLink
    case meetingAttendeeOrganizer
    case meetingAttendeeYou
    case meetingAttendeeOptional
    case meetingAttendeeAccepted
    case meetingAttendeeDeclined
    case meetingAttendeeTentative
    case meetingAttendeePending
    case meetingAttendeeDelegated
    case meetingAttendeeCompleted
    case meetingAttendeeInProcess
    case meetingAttendeeUnknown
    case meetingSelectCalendarEvent
    case meetingSelectCalendarEventHint
    case meetingNoNearbyCalendarEvents
    case meetingUseThisCalendarEvent
    case meetingCalendarAssociationFailedTitle
    case meetingCalendarAssociationFailedMessage
    case meetingNoSelectionTitle
    case meetingNoSelectionMessage
    case meetingSummarySaveErrorTitle
    case meetingSummarySaveErrorMessage
    case meetingTitlePlaceholder
    case meetingNotes
    case meetingTranscript
    case meetingManualNotesSaved
    case meetingManualNotesSaving
    case meetingManualNotesPlaceholder
    case meetingManualToolbarHeading
    case meetingManualToolbarBold
    case meetingManualToolbarBullet
    case meetingManualToolbarCheckbox
    case meetingStartRecording
    case meetingStartRecordingHelp
    case meetingSummarizing
    case meetingDone
    case meetingEdit
    case meetingStopRecording
    case meetingStopRecordingHelp
    case meetingDiscard
    case meetingShowRecording
    case meetingManageTemplates
    case meetingCopy
    case meetingExport
    case meetingExportTranscript
    case meetingExportNotes
    case meetingExportFull
    case meetingOpenSettings
    case meetingApplyTemplate
    case meetingResummarize
    case meetingTranscriptCallout(action: String)
    case meetingAddApiKey
    case meetingWords(count: Int)
    case meetingBuiltInTemplates
    case meetingCustomTemplates
    case meetingMerge
    case meetingMergeSelectNotes
    case meetingMergeNoCandidates
    case meetingMergeSelected(count: Int)
    case meetingMergeReSummarize
    case meetingMergeKeepSummary
    case meetingMergeSheetTitle
    case meetingMergeSheetMessage
    case meetingMergeProcessing
    case meetingMergeFailedTitle
    case meetingMergeBlockedRetainedRecording
    case meetingMergeBlockedLiveState
    case meetingMergeOnlyBlockedCandidates
    case meetingMergedSourcesSection
    case meetingOpenMergedSource
    case meetingTranscriptUnavailable
    case meetingLiveTranscriptToggleExpand
    case meetingLiveTranscriptToggleCollapse
    case meetingLiveTranscriptPlaceholder
    case meetingLiveChatPlaceholder
    case meetingChatPlaceholderMeeting
    case meetingChatPlaceholderFolder
    case meetingChatClear
    case meetingChatSend
    case meetingChatMoreContext
    case meetingChatIncludeTranscript
    case meetingChatTranscriptNeedsMention
    case meetingChatMentionMeeting
    case meetingMergedNotesSection
    case templateManagerTitle
    case templateManagerSubtitle
    case templateManagerNew
    case templateManagerDone
    case templateManagerCloseHelp
    case templateManagerFinishEditingHelp
    case templateManagerDeleteMessage
    case templateManagerEmpty
    case templateManagerEdit
    case templateManagerNewTitle
    case templateManagerEditTitle
    case templateManagerName
    case templateManagerPrompt
    case templateManagerNameValidation
    case templateManagerPromptValidation
    case templateManagerCreate
    case templateManagerSave
    case templateManagerCustom
    case templateManagerUseAsDefault
    case templateManagerDefaultBadge
    case templateManagerAutoBadge
    case templateManagerVisible
    case templateManagerSystemPrompts
    case templateManagerMeetingTitlePrompt
    case templateManagerMeetingTitlePromptDescription
    case templateManagerMeetingTitlePromptEditTitle
    case templateManagerRestoreDefault
    case templateManagerRestoreDefaultHelp
    case settingsTitle
    case settingsPaneGeneral
    case settingsPaneVoiceAndDictation
    case settingsPaneDictation
    case settingsPaneMeetings
    case settingsPaneAppearance
    case settingsSectionApplication
    case settingsSectionShortcuts
    case settingsSectionSync
    case settingsSectionPrivacyPermissions
    case settingsSectionAiCleanup
    case settingsGeneralSection
    case settingsLaunchAtLogin
    case settingsOpenDashboardOnLaunch
    case settingsDataSection
    case settingsClearDictationHistory
    case settingsClearMeetingHistory
    case settingsStopRecordingBeforeClearing
    case settingsPermissionsSection
    case settingsPermissionMicrophone
    case settingsPermissionAccessibility
    case settingsPermissionInputMonitoring
    case settingsPermissionScreenRecording
    case settingsPermissionSystemAudio
    case settingsGranted
    case settingsGrant
    case settingsOpenInSystemSettings
    case settingsConfirmDestructiveAction
    case settingsClearMeetingHistoryMessage
    case settingsTranscriptionSection
    case settingsDictationModel
    case settingsCohereLanguage
    case settingsAiTranscriptCleanup
    case settingsCleanupModel
    case settingsDownloadCleanupModelHint
    case settingsAppContext
    case settingsSharedContextDescription
    case settingsMeetingTranscriptionSection
    case settingsMeetingModel
    case settingsLiveMeetingTranscript
    case settingsMeetingContext
    case settingsMeetingSummariesSection
    case settingsSummaryBackend
    case settingsAccount
    case settingsModel
    case settingsFreeModel
    case settingsCustomModelID
    case settingsApiKey
    case settingsDefaultTemplate
    case settingsTemplates
    case settingsRecordingSection
    case settingsAutoRecordCalendarMeetings
    case settingsAutoRecordQuickNotes
    case settingsNotifyWhenMeetingDetected
    case settingsSaveMeetingRecording
    case settingsAdvancedSection
    case settingsEnablePostMeetingHook
    case settingsHookScript
    case settingsTimeout
    case settingsSeconds(count: Int)
    case settingsAdvancedHookDescription
    case settingsCalendarSection
    case settingsGoogleCalendar
    case settingsLocalCalendars
    case settingsLocalCalendarsHint
    case settingsNoLocalCalendarsFound
    case settingsGoogleCalendarUnavailable
    case settingsFloatingIndicatorSection
    case settingsShowFloatingIndicator
    case settingsIndicatorPosition
    case settingsAppearanceSection
    case settingsTheme
    case settingsDarkMode
    case settingsMenuBarIcon
    case settingsAccentColor
    case settingsPlaySoundEffects
    case settingsShowNextMeetingInMenuBar
    case settingsMaraudersMapSection
    case settingsMeetingCountdownAudio
    case settingsMischiefManaged
    case settingsSignedInSignOut
    case settingsSigningIn
    case settingsSignInWithChatGPT
    case settingsConnectedDisconnect
    case settingsConnecting
    case settingsConnectGoogleCalendar
    case settingsGoogleOAuthPending
    case settingsChooseAudioClip
    case settingsChooseHookScriptTitle
    case settingsChooseScriptPrompt
    case settingsChooseScriptEllipsis
    case settingsNoHookScriptSelected
    case settingsClearHookScript
    case settingsChooseHookScript
    case settingsNoApiKeyConfigured
    case settingsApiKeyConfigured
    case settingsLoadingModels
    case settingsLoadModels
    case quickNoteButton
    case quickNoteButtonShort
    case quickNoteButtonHelp
    case titlebarToggleSidebarHelp
    case settingsRecordingSaveNever
    case settingsRecordingSavePrompt
    case settingsRecordingSaveAlways
    case settingsDefaultTemplateAuto
    case settingsCustomIndicatorPosition
    case settingsThemeWarm
    case settingsThemeNeutral
    case settingsThemeGraphite
    case dictationsNoDictationsTitle
    case dictationsHoldToStart(hotkey: String)
    case dictationsTodayHeader
    case dictationsYesterdayHeader
    case dictationsCopy
    case dictationsDeleteTitle
    case dictationsDeleteMessage
    case dictionaryTitle
    case dictionaryAddNew
    case dictionaryDescription
    case dictionaryEmptyTitle
    case dictionaryEmptyMessage
    case dictionaryWordPlaceholder
    case dictionaryReplacementPlaceholder
    case dictionaryMatchingThreshold
    case dictionaryAdd
    case dictionarySave
    case shortcutsTitle
    case syncTitle
    case shortcutsDescription
    case shortcutsPushToTalk
    case shortcutsPushToTalkHint
    case shortcutsPressModifier
    case shortcutsChangeShortcut
    case shortcutsHandsFreeMode
    case shortcutsHandsFreeHint
    case shortcutsResetDefault
    case aboutTitle
    case aboutAppInfoSection
    case aboutVersion
    case aboutCheckForUpdates
    case aboutCheckNow
    case aboutSupportSection
    case aboutSupportDevelopment
    case aboutDonate
    case aboutSourceCode
    case aboutViewOnGitHub
    case aboutDataSection
    case aboutAppDataDirectory
    case aboutOpen
    case aboutAcknowledgementsSection
    case aboutInstallUpdate
    case aboutTryAgain
    case aboutCheckingForUpdatesTitle
    case aboutCheckingForUpdatesMessage
    case aboutUpdaterBusyTitle
    case aboutUpdateAvailableTitle(version: String)
    case aboutUpdateAvailableMessage
    case aboutUpdateReadyTitle(version: String)
    case aboutUpdateReadyMessage
    case aboutInstallingUpdateTitle(version: String)
    case aboutInstallingUpdateMessage
    case aboutUpToDateTitle
    case aboutUpToDateMessage
    case aboutUpdatesDisabledTitle
    case aboutUpdateCheckFailedTitle
    case statsDayStreak
    case statsWordsDictated
    case statsAvgWPM
    case statsMeetings
    case templateManagerIcon
    case templateManagerNamePlaceholder
    case statusLabel(text: String)
    case statusIdle
    case statusOpenApp(name: String)
    case statusStopMeetingRecording
    case statusStartMeetingRecording
    case statusDiscardMeetingRecording
    case statusRecentDictations
    case statusNoDictationsYet
    case statusTranscriptionBackend
    case statusMeetingsBackend
    case statusSettings
    case statusCheckForUpdates
    case statusQuit
    case statusStartsIn(value: String)
    case commonOK
}

enum L10n {
    static func text(_ key: L10nKey, config: AppConfig) -> String {
        text(key, language: config.resolvedAppLanguage)
    }

    static func text(_ key: L10nKey, language: AppLanguage) -> String {
        switch language.effectiveLanguageCode {
        case "es":
            return spanish(key)
        default:
            return english(key)
        }
    }

    private static func english(_ key: L10nKey) -> String {
        switch key {
        case .sidebarUpdateNow: return "Update Now"
        case .sidebarRestart: return "Restart"
        case .sidebarUpdateAvailable: return "Update available"
        case .sidebarUpdateReady: return "Update ready to install"
        case .sidebarUpdateTooltip: return "Open About to install the update"
        case .sidebarRestartTooltip: return "Open About to finish installing the update"
        case .sidebarDictations: return "Dictations"
        case .sidebarMeetings: return "Meetings"
        case .sidebarDictionary: return "Dictionary"
        case .sidebarModels: return "Models"
        case .sidebarShortcuts: return "Shortcuts"
        case .sidebarSettings: return "Settings"
        case .sidebarAbout: return "About"
        case .sidebarDelete: return "Delete"
        case .sidebarCancel: return "Cancel"
        case .sidebarMeetingsMovedToUnfiled(let count):
            return "\(count) meeting\(count == 1 ? "" : "s") in this folder will be moved to Unfiled."
        case .sidebarFolderRemoved:
            return "This folder will be permanently removed."
        case .sidebarGreeting(let name):
            return "Hi, \(name)"
        case .sidebarSearchPlaceholder:
            return "Search..."
        case .sidebarNewMeetingFolder:
            return "New Meeting Folder"
        case .sidebarAllMeetings:
            return "All Meetings"
        case .sidebarRename:
            return "Rename"
        case .sidebarAddSubfolder:
            return "Add Subfolder"
        case .sidebarFolderName:
            return "Folder name"
        case .sidebarNewFolder:
            return "New Folder"
        case .sidebarFolderColor:
            return "Color"
        case .sidebarFolderNoColor:
            return "No color"
        case .sidebarFolderColorGray:
            return "Gray"
        case .sidebarFolderColorBlue:
            return "Blue"
        case .sidebarFolderColorGreen:
            return "Green"
        case .sidebarFolderColorAmber:
            return "Amber"
        case .sidebarFolderColorOrange:
            return "Orange"
        case .sidebarFolderColorYellow:
            return "Yellow"
        case .sidebarFolderColorRed:
            return "Red"
        case .sidebarFolderColorPurple:
            return "Purple"
        case .sidebarFolderColorPink:
            return "Pink"
        case .sidebarFolderColorCyan:
            return "Cyan"
        case .sidebarFolderColorIndigo:
            return "Indigo"
        case .sidebarFolderColorBrown:
            return "Brown"
        case .settingsLanguage:
            return "Language"
        case .meetingsFilterAllTime:
            return "All time"
        case .meetingsFilterLast2Days:
            return "Last 2 days"
        case .meetingsFilterLastWeek:
            return "Last week"
        case .meetingsFilterLast2Weeks:
            return "Last 2 weeks"
        case .meetingsFilterLastMonth:
            return "Last month"
        case .meetingsFilterLast3Months:
            return "Last 3 months"
        case .meetingsSortNewestFirst:
            return "Newest first"
        case .meetingsSortOldestFirst:
            return "Oldest first"
        case .meetingsToday:
            return "Today"
        case .meetingsTomorrow:
            return "Tomorrow"
        case .meetingsComingUp:
            return "Coming Up"
        case .meetingsCollapseComingUp:
            return "Collapse"
        case .meetingsExpandComingUp:
            return "Expand"
        case .meetingsCollapsedHint:
            return "Section collapsed"
        case .meetingsCalendarSyncHint:
            return "Add Google to macOS Calendar for real-time sync"
        case .meetingsJoinAndRecord:
            return "Join & Record"
        case .meetingsPopupUpcomingTitle:
            return "Upcoming meeting"
        case .meetingsPopupStartingNowTitle:
            return "Meeting starting now"
        case .meetingsPopupStartRecording:
            return "Start Recording"
        case .meetingsPopupJoinOnly:
            return "Join Only"
        case .meetingsPopupRecordOnly:
            return "Record Only"
        case .meetingsPopupStartsInMinutes(let count):
            return "starts in \(count) min"
        case .meetingsPopupStartingNow:
            return "starting now"
        case .meetingsPopupStartedMinutesAgo(let count):
            return "started \(count) min ago"
        case .meetingsPopupDetectedTitle:
            return "Meeting detected"
        case .meetingsPopupTranscriptionCompleteTitle:
            return "Transcription complete"
        case .meetingsPopupViewNotes:
            return "View Notes"
        case .meetingsPopupEndedTitle:
            return "Meeting ended"
        case .meetingsPopupScheduledTimeOver:
            return "scheduled time is over"
        case .meetingsAddToFolder:
            return "Add to folder"
        case .meetingsHideFromComingUp:
            return "Hide from Coming Up"
        case .meetingsCount(let count):
            return "\(count) meeting\(count == 1 ? "" : "s")"
        case .meetingsHeaderHint:
            return "Open a meeting to review notes, transcript, and template-driven summaries"
        case .meetingsManageTemplates:
            return "Manage Templates"
        case .meetingsEditFolder:
            return "Edit Folder"
        case .meetingsNewSubfolder:
            return "New Subfolder"
        case .meetingsFolderEditorTitle:
            return "Folder Details"
        case .meetingsFolderParent:
            return "Parent folder"
        case .meetingsFolderRoot:
            return "Root level"
        case .meetingsFolderAppearance:
            return "Appearance"
        case .meetingsFolderIcon:
            return "Icon"
        case .meetingsFolderSave:
            return "Save"
        case .meetingsEmptyTitle:
            return "No meetings yet"
        case .meetingsEmptyFolderTitle:
            return "No meetings in this folder"
        case .meetingsEmptyMessage:
            return "Start a recording from the menu bar to create your first meeting note."
        case .meetingsEmptyFolderMessage:
            return "Choose another folder or move a meeting here from the browser."
        case .meetingDeleteTitle:
            return "Delete Meeting"
        case .meetingDeleteMessage:
            return "Are you sure you want to delete this meeting? Saved notes, transcript, and any retained recording will be removed."
        case .meetingMoveToFolder:
            return "Move to folder"
        case .meetingUnfiled:
            return "Unfiled"
        case .meetingNewFolderEllipsis:
            return "New Folder..."
        case .meetingNewFolderTitle:
            return "New Folder"
        case .meetingCreate:
            return "Create"
        case .meetingNewFolderMessage:
            return "Create a new folder and move this meeting into it."
        case .meetingDeleteHelp:
            return "Delete meeting"
        case .meetingBackToMeetings:
            return "Back to Meetings"
        case .meetingAssociateEvent:
            return "Associate event"
        case .meetingCalendarLinked:
            return "Calendar linked"
        case .meetingAssociatedEvent:
            return "Associated Event"
        case .meetingAttendees:
            return "Attendees"
        case .meetingOpenJoinLink:
            return "Open meeting"
        case .meetingAttendeeOrganizer:
            return "Organizer"
        case .meetingAttendeeYou:
            return "You"
        case .meetingAttendeeOptional:
            return "Optional"
        case .meetingAttendeeAccepted:
            return "Accepted"
        case .meetingAttendeeDeclined:
            return "Declined"
        case .meetingAttendeeTentative:
            return "Tentative"
        case .meetingAttendeePending:
            return "Pending"
        case .meetingAttendeeDelegated:
            return "Delegated"
        case .meetingAttendeeCompleted:
            return "Completed"
        case .meetingAttendeeInProcess:
            return "In progress"
        case .meetingAttendeeUnknown:
            return "Unknown"
        case .meetingSelectCalendarEvent:
            return "Select a calendar event"
        case .meetingSelectCalendarEventHint:
            return "Choose the meeting invite that best matches this recording."
        case .meetingNoNearbyCalendarEvents:
            return "No nearby calendar events found for this meeting."
        case .meetingUseThisCalendarEvent:
            return "Use this event"
        case .meetingCalendarAssociationFailedTitle:
            return "Couldn't associate calendar event"
        case .meetingCalendarAssociationFailedMessage:
            return "The selected calendar event could not be linked to this meeting."
        case .meetingNoSelectionTitle:
            return "No meeting selected"
        case .meetingNoSelectionMessage:
            return "Choose a meeting from the Meetings browser to open it here."
        case .meetingSummarySaveErrorTitle:
            return "Couldn't Save Summary"
        case .meetingSummarySaveErrorMessage:
            return "The updated meeting notes could not be saved."
        case .meetingTitlePlaceholder:
            return "Meeting Title"
        case .meetingNotes:
            return "Notes"
        case .meetingTranscript:
            return "Transcript"
        case .meetingManualNotesSaved:
            return "Saved"
        case .meetingManualNotesSaving:
            return "Saving..."
        case .meetingManualNotesPlaceholder:
            return "Write notes here..."
        case .meetingManualToolbarHeading:
            return "Heading"
        case .meetingManualToolbarBold:
            return "Bold"
        case .meetingManualToolbarBullet:
            return "Bullet"
        case .meetingManualToolbarCheckbox:
            return "Checkbox"
        case .meetingStartRecording:
            return "Record"
        case .meetingStartRecordingHelp:
            return "Start recording for this note"
        case .meetingSummarizing:
            return "Summarizing..."
        case .meetingDone:
            return "Done"
        case .meetingEdit:
            return "Edit"
        case .meetingStopRecording:
            return "Stop Recording"
        case .meetingStopRecordingHelp:
            return "Stop recording"
        case .meetingDiscard:
            return "Discard"
        case .meetingShowRecording:
            return "Show Recording"
        case .meetingManageTemplates:
            return "Manage Templates..."
        case .meetingCopy:
            return "Copy"
        case .meetingExport:
            return "Export"
        case .meetingExportTranscript:
            return "Export Transcript"
        case .meetingExportNotes:
            return "Export Notes"
        case .meetingExportFull:
            return "Export Full Meeting"
        case .meetingOpenSettings:
            return "Open Settings"
        case .meetingApplyTemplate:
            return "Apply Template"
        case .meetingResummarize:
            return "Re-summarize"
        case .meetingTranscriptCallout(let action):
            return "Use \(action) to turn this raw transcript into AI meeting notes and a cleaned-up title."
        case .meetingAddApiKey:
            return "Add your API key in Settings to generate meeting notes"
        case .meetingWords(let count):
            return "\(count) words"
        case .meetingBuiltInTemplates:
            return "Built-in Templates"
        case .meetingCustomTemplates:
            return "Custom Templates"
        case .meetingMerge:
            return "Merge"
        case .meetingMergeSelectNotes:
            return "Select notes to merge"
        case .meetingMergeNoCandidates:
            return "No merge candidates available for this meeting."
        case .meetingMergeSelected(let count):
            return count == 1 ? "1 note selected" : "\(count) notes selected"
        case .meetingMergeReSummarize:
            return "Merge and Summarize"
        case .meetingMergeKeepSummary:
            return "Merge"
        case .meetingMergeSheetTitle:
            return "Merge meeting notes"
        case .meetingMergeSheetMessage:
            return "Choose the notes that belong to this same calendar meeting."
        case .meetingMergeProcessing:
            return "Merging..."
        case .meetingMergeFailedTitle:
            return "Couldn't merge notes"
        case .meetingMergeBlockedRetainedRecording:
            return "Keeps a saved recording, so merging it would hide that audio."
        case .meetingMergeBlockedLiveState:
            return "This note is still recording or processing, so it cannot be merged yet."
        case .meetingMergeOnlyBlockedCandidates:
            return "Related notes were found for this meeting, but they are still recording or processing."
        case .meetingMergedSourcesSection:
            return "Merged related notes"
        case .meetingOpenMergedSource:
            return "Open related note"
        case .meetingTranscriptUnavailable:
            return "No transcript is available for this note yet."
        case .meetingLiveTranscriptToggleExpand:
            return "Show live transcript"
        case .meetingLiveTranscriptToggleCollapse:
            return "Hide live transcript"
        case .meetingLiveTranscriptPlaceholder:
            return "Live transcript will appear here as the meeting is transcribed."
        case .meetingLiveChatPlaceholder:
            return "Ask anything (coming soon)"
        case .meetingChatPlaceholderMeeting:
            return "Ask about Meeting"
        case .meetingChatPlaceholderFolder:
            return "Ask about Folder"
        case .meetingChatClear:
            return "Clear chat"
        case .meetingChatSend:
            return "Send"
        case .meetingChatMoreContext:
            return "Context"
        case .meetingChatIncludeTranscript:
            return "Include transcript"
        case .meetingChatTranscriptNeedsMention:
            return "Mention a meeting with @ first"
        case .meetingChatMentionMeeting:
            return "Mention meeting"
        case .meetingMergedNotesSection:
            return "Merged notes"
        case .templateManagerTitle:
            return "Manage Templates"
        case .templateManagerSubtitle:
            return "Create reusable prompt-based note formats for meetings."
        case .templateManagerNew:
            return "New template"
        case .templateManagerDone:
            return "Done"
        case .templateManagerCloseHelp:
            return "Close template manager"
        case .templateManagerFinishEditingHelp:
            return "Finish or cancel template editing before closing."
        case .templateManagerDeleteMessage:
            return "This template will be permanently removed. Existing meetings will keep their saved template snapshot."
        case .templateManagerEmpty:
            return "No custom templates yet."
        case .templateManagerEdit:
            return "Edit"
        case .templateManagerNewTitle:
            return "New template"
        case .templateManagerEditTitle:
            return "Edit template"
        case .templateManagerName:
            return "Name"
        case .templateManagerPrompt:
            return "Prompt"
        case .templateManagerNameValidation:
            return "Enter a template name."
        case .templateManagerPromptValidation:
            return "Enter the prompt instructions for this template."
        case .templateManagerCreate:
            return "Create template"
        case .templateManagerSave:
            return "Save changes"
        case .templateManagerCustom:
            return "Custom"
        case .templateManagerUseAsDefault:
            return "Use as default"
        case .templateManagerDefaultBadge:
            return "Default"
        case .templateManagerAutoBadge:
            return "Auto"
        case .templateManagerVisible:
            return "Visible"
        case .templateManagerSystemPrompts:
            return "System Prompts"
        case .templateManagerMeetingTitlePrompt:
            return "Meeting Title"
        case .templateManagerMeetingTitlePromptDescription:
            return "Controls how Muesli generates the automatic title for a meeting from the transcript."
        case .templateManagerMeetingTitlePromptEditTitle:
            return "Edit Meeting Title Prompt"
        case .templateManagerRestoreDefault:
            return "Restore default"
        case .templateManagerRestoreDefaultHelp:
            return "Revert this prompt to Muesli's built-in default."
        case .settingsTitle:
            return "Settings"
        case .settingsPaneGeneral:
            return "General"
        case .settingsPaneVoiceAndDictation:
            return "Voice & Dictation"
        case .settingsPaneDictation:
            return "Dictation"
        case .settingsPaneMeetings:
            return "Meetings"
        case .settingsPaneAppearance:
            return "Appearance"
        case .settingsSectionApplication:
            return "Application"
        case .settingsSectionShortcuts:
            return "Shortcuts"
        case .settingsSectionSync:
            return "Sync"
        case .settingsSectionPrivacyPermissions:
            return "Privacy & Permissions"
        case .settingsSectionAiCleanup:
            return "AI Cleanup"
        case .settingsGeneralSection:
            return "General"
        case .settingsLaunchAtLogin:
            return "Launch at login"
        case .settingsOpenDashboardOnLaunch:
            return "Open dashboard on launch"
        case .settingsDataSection:
            return "Data"
        case .settingsClearDictationHistory:
            return "Clear dictation history"
        case .settingsClearMeetingHistory:
            return "Clear meeting history"
        case .settingsStopRecordingBeforeClearing:
            return "Stop the current meeting recording before clearing meeting history."
        case .settingsPermissionsSection:
            return "Permissions"
        case .settingsPermissionMicrophone:
            return "Microphone"
        case .settingsPermissionAccessibility:
            return "Accessibility"
        case .settingsPermissionInputMonitoring:
            return "Input Monitoring"
        case .settingsPermissionScreenRecording:
            return "Screen Recording"
        case .settingsPermissionSystemAudio:
            return "System Audio"
        case .settingsGranted:
            return "Granted"
        case .settingsGrant:
            return "Grant"
        case .settingsOpenInSystemSettings:
            return "Open in System Settings"
        case .settingsConfirmDestructiveAction:
            return "Confirm Destructive Action"
        case .settingsClearMeetingHistoryMessage:
            return "This will permanently remove all saved meetings, notes, transcripts, and retained audio recordings. This cannot be undone."
        case .settingsTranscriptionSection:
            return "Transcription"
        case .settingsDictationModel:
            return "Dictation model"
        case .settingsCohereLanguage:
            return "Cohere language"
        case .settingsAiTranscriptCleanup:
            return "AI transcript cleanup"
        case .settingsCleanupModel:
            return "Cleanup model"
        case .settingsDownloadCleanupModelHint:
            return "Download a cleanup model in Models"
        case .settingsAppContext:
            return "App context"
        case .settingsSharedContextDescription:
            return "Uses nearby app text for dictation cleanup and meeting summaries, plus OCR context for meetings when available. All processing stays on-device."
        case .settingsMeetingTranscriptionSection:
            return "Meeting Transcription"
        case .settingsMeetingModel:
            return "Meeting model"
        case .settingsLiveMeetingTranscript:
            return "Live transcript"
        case .settingsMeetingContext:
            return "Meeting context"
        case .settingsMeetingSummariesSection:
            return "Meeting Summaries"
        case .settingsSummaryBackend:
            return "Summary backend"
        case .settingsAccount:
            return "Account"
        case .settingsModel:
            return "Model"
        case .settingsFreeModel:
            return "Free model"
        case .settingsCustomModelID:
            return "Custom model ID"
        case .settingsApiKey:
            return "API Key"
        case .settingsDefaultTemplate:
            return "Default template"
        case .settingsTemplates:
            return "Templates"
        case .settingsRecordingSection:
            return "Recording"
        case .settingsAutoRecordCalendarMeetings:
            return "Auto-record calendar meetings"
        case .settingsAutoRecordQuickNotes:
            return "Auto-record Quick Notes"
        case .settingsNotifyWhenMeetingDetected:
            return "Notify when meeting detected"
        case .settingsSaveMeetingRecording:
            return "Save meeting recording"
        case .settingsAdvancedSection:
            return "Advanced"
        case .settingsEnablePostMeetingHook:
            return "Enable post-meeting hook"
        case .settingsHookScript:
            return "Hook script"
        case .settingsTimeout:
            return "Timeout"
        case .settingsSeconds(let count):
            return "\(count) seconds"
        case .settingsAdvancedHookDescription:
            return "Advanced: runs a user-supplied executable after each completed meeting. The executable receives JSON on stdin and must already be runnable on its own."
        case .settingsCalendarSection:
            return "Calendar"
        case .settingsGoogleCalendar:
            return "Google Calendar"
        case .settingsLocalCalendars:
            return "Local calendars"
        case .settingsLocalCalendarsHint:
            return "Choose which macOS calendars Muesli should use for upcoming meetings, prompts, and detection."
        case .settingsNoLocalCalendarsFound:
            return "No local calendars were found."
        case .settingsGoogleCalendarUnavailable:
            return "Google Calendar credentials not configured."
        case .settingsFloatingIndicatorSection:
            return "Floating Indicator"
        case .settingsShowFloatingIndicator:
            return "Show floating indicator"
        case .settingsIndicatorPosition:
            return "Indicator position"
        case .settingsAppearanceSection:
            return "Appearance"
        case .settingsTheme:
            return "Theme"
        case .settingsDarkMode:
            return "Dark mode"
        case .settingsMenuBarIcon:
            return "Menu bar icon"
        case .settingsAccentColor:
            return "Accent color"
        case .settingsPlaySoundEffects:
            return "Play sound effects"
        case .settingsShowNextMeetingInMenuBar:
            return "Show next meeting in menu bar"
        case .settingsMaraudersMapSection:
            return "Marauder's Map"
        case .settingsMeetingCountdownAudio:
            return "Meeting countdown audio"
        case .settingsMischiefManaged:
            return "Mischief Managed"
        case .settingsSignedInSignOut:
            return "Signed in · Sign Out"
        case .settingsSigningIn:
            return "Signing in..."
        case .settingsSignInWithChatGPT:
            return "Sign in with ChatGPT"
        case .settingsConnectedDisconnect:
            return "Connected · Disconnect"
        case .settingsConnecting:
            return "Connecting..."
        case .settingsConnectGoogleCalendar:
            return "Connect Google Calendar"
        case .settingsGoogleOAuthPending:
            return "Google OAuth verification pending"
        case .settingsChooseAudioClip:
            return "Choose an audio clip"
        case .settingsChooseHookScriptTitle:
            return "Choose a hook script"
        case .settingsChooseScriptPrompt:
            return "Choose Script"
        case .settingsChooseScriptEllipsis:
            return "Choose a script..."
        case .settingsNoHookScriptSelected:
            return "No hook script selected"
        case .settingsClearHookScript:
            return "Clear hook script"
        case .settingsChooseHookScript:
            return "Choose hook script"
        case .settingsNoApiKeyConfigured:
            return "No API key configured"
        case .settingsApiKeyConfigured:
            return "Key configured"
        case .settingsLoadingModels:
            return "Loading models"
        case .settingsLoadModels:
            return "Load"
        case .quickNoteButton:
            return "Quick Note"
        case .quickNoteButtonShort:
            return "Note"
        case .quickNoteButtonHelp:
            return "Start a quick meeting note"
        case .titlebarToggleSidebarHelp:
            return "Toggle sidebar"
        case .settingsRecordingSaveNever:
            return "Never"
        case .settingsRecordingSavePrompt:
            return "Ask every time"
        case .settingsRecordingSaveAlways:
            return "Always"
        case .settingsDefaultTemplateAuto:
            return "Auto"
        case .settingsCustomIndicatorPosition:
            return "Custom (drag to reposition)"
        case .settingsThemeWarm:
            return "Calido"
        case .settingsThemeNeutral:
            return "Neutro"
        case .settingsThemeGraphite:
            return "Grafito"
        case .dictationsNoDictationsTitle:
            return "No dictations yet"
        case .dictationsHoldToStart(let hotkey):
            return "Hold \(hotkey) to start dictating"
        case .dictationsTodayHeader:
            return "TODAY"
        case .dictationsYesterdayHeader:
            return "YESTERDAY"
        case .dictationsCopy:
            return "Copy"
        case .dictationsDeleteTitle:
            return "Delete Dictation"
        case .dictationsDeleteMessage:
            return "Are you sure you want to delete this dictation? This cannot be undone."
        case .dictionaryTitle:
            return "Dictionary"
        case .dictionaryAddNew:
            return "Add new"
        case .dictionaryDescription:
            return "Add custom words for names, brands, and domain terms, and tune how aggressively each entry should fuzzy-match transcription errors."
        case .dictionaryEmptyTitle:
            return "No custom words yet"
        case .dictionaryEmptyMessage:
            return "Add words that transcription frequently gets wrong"
        case .dictionaryWordPlaceholder:
            return "Word"
        case .dictionaryReplacementPlaceholder:
            return "Replace with (optional)"
        case .dictionaryMatchingThreshold:
            return "Matching threshold"
        case .dictionaryAdd:
            return "Add"
        case .dictionarySave:
            return "Save"
        case .shortcutsTitle:
            return "Shortcuts"
        case .syncTitle:
            return "Sync"
        case .shortcutsDescription:
            return "Choose your preferred shortcut for dictation."
        case .shortcutsPushToTalk:
            return "Push to Talk"
        case .shortcutsPushToTalkHint:
            return "Hold to record, release to transcribe"
        case .shortcutsPressModifier:
            return "Press a modifier key..."
        case .shortcutsChangeShortcut:
            return "Change Shortcut"
        case .shortcutsHandsFreeMode:
            return "Hands-Free Mode"
        case .shortcutsHandsFreeHint:
            return "Double-tap to start, tap again to stop"
        case .shortcutsResetDefault:
            return "Reset to Default"
        case .aboutTitle:
            return "About"
        case .aboutAppInfoSection:
            return "App Info"
        case .aboutVersion:
            return "Version"
        case .aboutCheckForUpdates:
            return "Check for Updates"
        case .aboutCheckNow:
            return "Check Now"
        case .aboutSupportSection:
            return "Support"
        case .aboutSupportDevelopment:
            return "Support Development"
        case .aboutDonate:
            return "Donate"
        case .aboutSourceCode:
            return "Source Code"
        case .aboutViewOnGitHub:
            return "View on GitHub"
        case .aboutDataSection:
            return "Data"
        case .aboutAppDataDirectory:
            return "App Data Directory"
        case .aboutOpen:
            return "Open"
        case .aboutAcknowledgementsSection:
            return "Acknowledgements"
        case .aboutInstallUpdate:
            return "Install Update"
        case .aboutTryAgain:
            return "Try Again"
        case .aboutCheckingForUpdatesTitle:
            return "Checking for updates"
        case .aboutCheckingForUpdatesMessage:
            return "Muesli is checking the appcast for the latest version."
        case .aboutUpdaterBusyTitle:
            return "Updater is busy"
        case .aboutUpdateAvailableTitle(let version):
            return "Muesli \(version) is available"
        case .aboutUpdateAvailableMessage:
            return "An update is available. Start the updater to download and install it."
        case .aboutUpdateReadyTitle(let version):
            return "Muesli \(version) is ready to install"
        case .aboutUpdateReadyMessage:
            return "Quit and reopen Muesli to finish installing the update."
        case .aboutInstallingUpdateTitle(let version):
            return "Installing Muesli \(version)"
        case .aboutInstallingUpdateMessage:
            return "Sparkle is preparing the update. Muesli may relaunch when installation finishes."
        case .aboutUpToDateTitle:
            return "Muesli is up to date"
        case .aboutUpToDateMessage:
            return "No newer version was found in the appcast."
        case .aboutUpdatesDisabledTitle:
            return "Updates are disabled"
        case .aboutUpdateCheckFailedTitle:
            return "Update check failed"
        case .statsDayStreak:
            return "day streak"
        case .statsWordsDictated:
            return "words dictated"
        case .statsAvgWPM:
            return "avg WPM"
        case .statsMeetings:
            return "meetings"
        case .templateManagerIcon:
            return "Icon"
        case .templateManagerNamePlaceholder:
            return "Customer follow-up"
        case .statusLabel(let text):
            return "Status: \(text)"
        case .statusIdle:
            return "Idle"
        case .statusOpenApp(let name):
            return "Open \(name)"
        case .statusStopMeetingRecording:
            return "Stop Meeting Recording"
        case .statusStartMeetingRecording:
            return "Start Meeting Recording"
        case .statusDiscardMeetingRecording:
            return "Discard Meeting Recording..."
        case .statusRecentDictations:
            return "Recent Dictations"
        case .statusNoDictationsYet:
            return "No dictations yet"
        case .statusTranscriptionBackend:
            return "Transcription Backend"
        case .statusMeetingsBackend:
            return "Meetings Backend"
        case .statusSettings:
            return "Settings..."
        case .statusCheckForUpdates:
            return "Check for Updates..."
        case .statusQuit:
            return "Quit"
        case .statusStartsIn(let value):
            return "Starts in \(value)"
        case .commonOK:
            return "OK"
        }
    }

    private static func spanish(_ key: L10nKey) -> String {
        switch key {
        case .sidebarUpdateNow: return "Actualizar"
        case .sidebarRestart: return "Reiniciar"
        case .sidebarUpdateAvailable: return "Actualizacion disponible"
        case .sidebarUpdateReady: return "Actualizacion lista para instalar"
        case .sidebarUpdateTooltip: return "Abre Acerca de para instalar la actualizacion"
        case .sidebarRestartTooltip: return "Abre Acerca de para terminar la instalacion"
        case .sidebarDictations: return "Dictados"
        case .sidebarMeetings: return "Reuniones"
        case .sidebarDictionary: return "Diccionario"
        case .sidebarModels: return "Modelos"
        case .sidebarShortcuts: return "Atajos"
        case .sidebarSettings: return "Ajustes"
        case .sidebarAbout: return "Acerca de"
        case .sidebarDelete: return "Eliminar"
        case .sidebarCancel: return "Cancelar"
        case .sidebarMeetingsMovedToUnfiled(let count):
            return "\(count) reunion\(count == 1 ? "" : "es") de esta carpeta se movera a Sin carpeta."
        case .sidebarFolderRemoved:
            return "Esta carpeta se eliminara permanentemente."
        case .sidebarGreeting(let name):
            return "Hola, \(name)"
        case .sidebarSearchPlaceholder:
            return "Buscar..."
        case .sidebarNewMeetingFolder:
            return "Nueva carpeta de reuniones"
        case .sidebarAllMeetings:
            return "Todas las reuniones"
        case .sidebarRename:
            return "Renombrar"
        case .sidebarAddSubfolder:
            return "Agregar subcarpeta"
        case .sidebarFolderName:
            return "Nombre de la carpeta"
        case .sidebarNewFolder:
            return "Nueva carpeta"
        case .sidebarFolderColor:
            return "Color"
        case .sidebarFolderNoColor:
            return "Sin color"
        case .sidebarFolderColorGray:
            return "Gris"
        case .sidebarFolderColorBlue:
            return "Azul"
        case .sidebarFolderColorGreen:
            return "Verde"
        case .sidebarFolderColorAmber:
            return "Ambar"
        case .sidebarFolderColorOrange:
            return "Naranja"
        case .sidebarFolderColorYellow:
            return "Amarillo"
        case .sidebarFolderColorRed:
            return "Rojo"
        case .sidebarFolderColorPurple:
            return "Morado"
        case .sidebarFolderColorPink:
            return "Rosa"
        case .sidebarFolderColorCyan:
            return "Cian"
        case .sidebarFolderColorIndigo:
            return "Indigo"
        case .sidebarFolderColorBrown:
            return "Marron"
        case .settingsLanguage:
            return "Idioma"
        case .meetingsFilterAllTime:
            return "Todo el tiempo"
        case .meetingsFilterLast2Days:
            return "Ultimos 2 dias"
        case .meetingsFilterLastWeek:
            return "Ultima semana"
        case .meetingsFilterLast2Weeks:
            return "Ultimas 2 semanas"
        case .meetingsFilterLastMonth:
            return "Ultimo mes"
        case .meetingsFilterLast3Months:
            return "Ultimos 3 meses"
        case .meetingsSortNewestFirst:
            return "Mas recientes primero"
        case .meetingsSortOldestFirst:
            return "Mas antiguas primero"
        case .meetingsToday:
            return "Hoy"
        case .meetingsTomorrow:
            return "Manana"
        case .meetingsComingUp:
            return "Proximamente"
        case .meetingsCollapseComingUp:
            return "Colapsar"
        case .meetingsExpandComingUp:
            return "Expandir"
        case .meetingsCollapsedHint:
            return "Seccion colapsada"
        case .meetingsCalendarSyncHint:
            return "Agrega Google al Calendario de macOS para sincronizacion en tiempo real"
        case .meetingsJoinAndRecord:
            return "Entrar y grabar"
        case .meetingsPopupUpcomingTitle:
            return "Proxima reunion"
        case .meetingsPopupStartingNowTitle:
            return "La reunion empieza ahora"
        case .meetingsPopupStartRecording:
            return "Empezar a grabar"
        case .meetingsPopupJoinOnly:
            return "Solo entrar"
        case .meetingsPopupRecordOnly:
            return "Solo grabar"
        case .meetingsPopupStartsInMinutes(let count):
            return "empieza en \(count) min"
        case .meetingsPopupStartingNow:
            return "empieza ahora"
        case .meetingsPopupStartedMinutesAgo(let count):
            return "empezo hace \(count) min"
        case .meetingsPopupDetectedTitle:
            return "Reunion detectada"
        case .meetingsPopupTranscriptionCompleteTitle:
            return "Transcripcion completada"
        case .meetingsPopupViewNotes:
            return "Ver notas"
        case .meetingsPopupEndedTitle:
            return "La reunion ha terminado"
        case .meetingsPopupScheduledTimeOver:
            return "el tiempo programado ha terminado"
        case .meetingsAddToFolder:
            return "Agregar a carpeta"
        case .meetingsHideFromComingUp:
            return "Ocultar de Proximamente"
        case .meetingsCount(let count):
            return "\(count) reunion\(count == 1 ? "" : "es")"
        case .meetingsHeaderHint:
            return "Abre una reunion para revisar notas, transcripcion y resumenes basados en plantillas"
        case .meetingsManageTemplates:
            return "Gestionar plantillas"
        case .meetingsEditFolder:
            return "Editar carpeta"
        case .meetingsNewSubfolder:
            return "Nueva subcarpeta"
        case .meetingsFolderEditorTitle:
            return "Detalles de la carpeta"
        case .meetingsFolderParent:
            return "Carpeta padre"
        case .meetingsFolderRoot:
            return "Nivel raiz"
        case .meetingsFolderAppearance:
            return "Apariencia"
        case .meetingsFolderIcon:
            return "Icono"
        case .meetingsFolderSave:
            return "Guardar"
        case .meetingsEmptyTitle:
            return "Aun no hay reuniones"
        case .meetingsEmptyFolderTitle:
            return "No hay reuniones en esta carpeta"
        case .meetingsEmptyMessage:
            return "Inicia una grabacion desde la barra de menu para crear tu primera nota de reunion."
        case .meetingsEmptyFolderMessage:
            return "Elige otra carpeta o mueve una reunion aqui desde el explorador."
        case .meetingDeleteTitle:
            return "Eliminar reunion"
        case .meetingDeleteMessage:
            return "Seguro que quieres eliminar esta reunion? Se borraran las notas guardadas, la transcripcion y cualquier grabacion retenida."
        case .meetingMoveToFolder:
            return "Mover a carpeta"
        case .meetingUnfiled:
            return "Sin carpeta"
        case .meetingNewFolderEllipsis:
            return "Nueva carpeta..."
        case .meetingNewFolderTitle:
            return "Nueva carpeta"
        case .meetingCreate:
            return "Crear"
        case .meetingNewFolderMessage:
            return "Crea una nueva carpeta y mueve esta reunion alli."
        case .meetingDeleteHelp:
            return "Eliminar reunion"
        case .meetingBackToMeetings:
            return "Volver a Reuniones"
        case .meetingAssociateEvent:
            return "Asociar cita"
        case .meetingCalendarLinked:
            return "Cita asociada"
        case .meetingAssociatedEvent:
            return "Evento asociado"
        case .meetingAttendees:
            return "Asistentes"
        case .meetingOpenJoinLink:
            return "Abrir reunion"
        case .meetingAttendeeOrganizer:
            return "Organizador"
        case .meetingAttendeeYou:
            return "Tu"
        case .meetingAttendeeOptional:
            return "Opcional"
        case .meetingAttendeeAccepted:
            return "Aceptado"
        case .meetingAttendeeDeclined:
            return "Rechazado"
        case .meetingAttendeeTentative:
            return "Tentativo"
        case .meetingAttendeePending:
            return "Pendiente"
        case .meetingAttendeeDelegated:
            return "Delegado"
        case .meetingAttendeeCompleted:
            return "Completado"
        case .meetingAttendeeInProcess:
            return "En curso"
        case .meetingAttendeeUnknown:
            return "Desconocido"
        case .meetingSelectCalendarEvent:
            return "Selecciona una cita"
        case .meetingSelectCalendarEventHint:
            return "Elige la invitacion de calendario que mejor coincide con esta grabacion."
        case .meetingNoNearbyCalendarEvents:
            return "No se encontraron citas cercanas para esta reunion."
        case .meetingUseThisCalendarEvent:
            return "Usar esta cita"
        case .meetingCalendarAssociationFailedTitle:
            return "No se pudo asociar la cita"
        case .meetingCalendarAssociationFailedMessage:
            return "No se pudo vincular la cita seleccionada con esta reunion."
        case .meetingNoSelectionTitle:
            return "No hay reunion seleccionada"
        case .meetingNoSelectionMessage:
            return "Elige una reunion desde el navegador de Reuniones para abrirla aqui."
        case .meetingSummarySaveErrorTitle:
            return "No se pudo guardar el resumen"
        case .meetingSummarySaveErrorMessage:
            return "No se pudieron guardar las notas actualizadas de la reunion."
        case .meetingTitlePlaceholder:
            return "Titulo de la reunion"
        case .meetingNotes:
            return "Notas"
        case .meetingTranscript:
            return "Transcripcion"
        case .meetingManualNotesSaved:
            return "Guardado"
        case .meetingManualNotesSaving:
            return "Guardando..."
        case .meetingManualNotesPlaceholder:
            return "Escribe notas aqui..."
        case .meetingManualToolbarHeading:
            return "Titulo"
        case .meetingManualToolbarBold:
            return "Negrita"
        case .meetingManualToolbarBullet:
            return "Vinetas"
        case .meetingManualToolbarCheckbox:
            return "Checklist"
        case .meetingStartRecording:
            return "Grabar"
        case .meetingStartRecordingHelp:
            return "Empezar a grabar para esta nota"
        case .meetingSummarizing:
            return "Resumiendo..."
        case .meetingDone:
            return "Listo"
        case .meetingEdit:
            return "Editar"
        case .meetingStopRecording:
            return "Detener grabacion"
        case .meetingStopRecordingHelp:
            return "Detener grabacion"
        case .meetingDiscard:
            return "Descartar"
        case .meetingShowRecording:
            return "Mostrar grabacion"
        case .meetingManageTemplates:
            return "Gestionar plantillas..."
        case .meetingCopy:
            return "Copiar"
        case .meetingExport:
            return "Exportar"
        case .meetingExportTranscript:
            return "Exportar transcripcion"
        case .meetingExportNotes:
            return "Exportar notas"
        case .meetingExportFull:
            return "Exportar reunion completa"
        case .meetingOpenSettings:
            return "Abrir ajustes"
        case .meetingApplyTemplate:
            return "Aplicar plantilla"
        case .meetingResummarize:
            return "Volver a resumir"
        case .meetingTranscriptCallout(let action):
            return "Usa \(action) para convertir esta transcripcion cruda en notas de reunion con IA y un titulo mas limpio."
        case .meetingAddApiKey:
            return "Agrega tu clave API en Ajustes para generar notas de reunion"
        case .meetingWords(let count):
            return "\(count) palabras"
        case .meetingBuiltInTemplates:
            return "Plantillas integradas"
        case .meetingCustomTemplates:
            return "Plantillas personalizadas"
        case .meetingMerge:
            return "Fusionar"
        case .meetingMergeSelectNotes:
            return "Selecciona notas para fusionar"
        case .meetingMergeNoCandidates:
            return "No hay candidatas para fusionar en esta reunion."
        case .meetingMergeSelected(let count):
            return count == 1 ? "1 nota seleccionada" : "\(count) notas seleccionadas"
        case .meetingMergeReSummarize:
            return "Fusionar y resumir"
        case .meetingMergeKeepSummary:
            return "Fusionar"
        case .meetingMergeSheetTitle:
            return "Fusionar notas de reunion"
        case .meetingMergeSheetMessage:
            return "Elige las notas que pertenecen a esta misma cita del calendario."
        case .meetingMergeProcessing:
            return "Fusionando..."
        case .meetingMergeFailedTitle:
            return "No se pudieron fusionar las notas"
        case .meetingMergeBlockedRetainedRecording:
            return "Conserva una grabacion guardada, asi que fusionarla ocultaria ese audio."
        case .meetingMergeBlockedLiveState:
            return "Esta nota sigue grabando o procesando, asi que aun no se puede fusionar."
        case .meetingMergeOnlyBlockedCandidates:
            return "Se encontraron notas relacionadas para esta reunion, pero todavia siguen grabando o procesando."
        case .meetingMergedSourcesSection:
            return "Notas relacionadas fusionadas"
        case .meetingOpenMergedSource:
            return "Abrir nota relacionada"
        case .meetingTranscriptUnavailable:
            return "Todavia no hay transcripcion disponible para esta nota."
        case .meetingLiveTranscriptToggleExpand:
            return "Mostrar transcripcion en vivo"
        case .meetingLiveTranscriptToggleCollapse:
            return "Ocultar transcripcion en vivo"
        case .meetingLiveTranscriptPlaceholder:
            return "La transcripcion en vivo aparecera aqui mientras se procesa la reunion."
        case .meetingLiveChatPlaceholder:
            return "Pregunta lo que quieras (proximamente)"
        case .meetingChatPlaceholderMeeting:
            return "Pregunta sobre la reunion"
        case .meetingChatPlaceholderFolder:
            return "Pregunta sobre la carpeta"
        case .meetingChatClear:
            return "Limpiar chat"
        case .meetingChatSend:
            return "Enviar"
        case .meetingChatMoreContext:
            return "Contexto"
        case .meetingChatIncludeTranscript:
            return "Incluir transcripcion"
        case .meetingChatTranscriptNeedsMention:
            return "Menciona una reunion con @ primero"
        case .meetingChatMentionMeeting:
            return "Mencionar reunion"
        case .meetingMergedNotesSection:
            return "Notas fusionadas"
        case .templateManagerTitle:
            return "Gestionar plantillas"
        case .templateManagerSubtitle:
            return "Crea formatos reutilizables de notas para reuniones basados en prompts."
        case .templateManagerNew:
            return "Nueva plantilla"
        case .templateManagerDone:
            return "Listo"
        case .templateManagerCloseHelp:
            return "Cerrar gestor de plantillas"
        case .templateManagerFinishEditingHelp:
            return "Termina o cancela la edicion de la plantilla antes de cerrar."
        case .templateManagerDeleteMessage:
            return "Esta plantilla se eliminara permanentemente. Las reuniones existentes conservaran su instantanea guardada."
        case .templateManagerEmpty:
            return "Aun no hay plantillas personalizadas."
        case .templateManagerEdit:
            return "Editar"
        case .templateManagerNewTitle:
            return "Nueva plantilla"
        case .templateManagerEditTitle:
            return "Editar plantilla"
        case .templateManagerName:
            return "Nombre"
        case .templateManagerPrompt:
            return "Prompt"
        case .templateManagerNameValidation:
            return "Introduce un nombre para la plantilla."
        case .templateManagerPromptValidation:
            return "Introduce las instrucciones del prompt para esta plantilla."
        case .templateManagerCreate:
            return "Crear plantilla"
        case .templateManagerSave:
            return "Guardar cambios"
        case .templateManagerCustom:
            return "Personalizada"
        case .templateManagerUseAsDefault:
            return "Usar por defecto"
        case .templateManagerDefaultBadge:
            return "Por defecto"
        case .templateManagerAutoBadge:
            return "Auto"
        case .templateManagerVisible:
            return "Visible"
        case .templateManagerSystemPrompts:
            return "Prompts del sistema"
        case .templateManagerMeetingTitlePrompt:
            return "Titulo de reunion"
        case .templateManagerMeetingTitlePromptDescription:
            return "Controla como Muesli genera automaticamente el titulo de una reunion a partir del transcript."
        case .templateManagerMeetingTitlePromptEditTitle:
            return "Editar prompt de titulo"
        case .templateManagerRestoreDefault:
            return "Restaurar por defecto"
        case .templateManagerRestoreDefaultHelp:
            return "Restablece este prompt al valor por defecto de Muesli."
        case .settingsTitle:
            return "Ajustes"
        case .settingsPaneGeneral:
            return "General"
        case .settingsPaneVoiceAndDictation:
            return "Voz y dictado"
        case .settingsPaneDictation:
            return "Dictado"
        case .settingsPaneMeetings:
            return "Reuniones"
        case .settingsPaneAppearance:
            return "Apariencia"
        case .settingsSectionApplication:
            return "Aplicacion"
        case .settingsSectionShortcuts:
            return "Atajos"
        case .settingsSectionSync:
            return "Sincronizacion"
        case .settingsSectionPrivacyPermissions:
            return "Privacidad y permisos"
        case .settingsSectionAiCleanup:
            return "Limpieza con IA"
        case .settingsGeneralSection:
            return "General"
        case .settingsLaunchAtLogin:
            return "Iniciar al abrir sesion"
        case .settingsOpenDashboardOnLaunch:
            return "Abrir panel al iniciar"
        case .settingsDataSection:
            return "Datos"
        case .settingsClearDictationHistory:
            return "Borrar historial de dictados"
        case .settingsClearMeetingHistory:
            return "Borrar historial de reuniones"
        case .settingsStopRecordingBeforeClearing:
            return "Deten la grabacion actual antes de borrar el historial de reuniones."
        case .settingsPermissionsSection:
            return "Permisos"
        case .settingsPermissionMicrophone:
            return "Microfono"
        case .settingsPermissionAccessibility:
            return "Accesibilidad"
        case .settingsPermissionInputMonitoring:
            return "Monitorizacion de entrada"
        case .settingsPermissionScreenRecording:
            return "Grabacion de pantalla"
        case .settingsPermissionSystemAudio:
            return "Audio del sistema"
        case .settingsGranted:
            return "Concedido"
        case .settingsGrant:
            return "Conceder"
        case .settingsOpenInSystemSettings:
            return "Abrir en Ajustes del sistema"
        case .settingsConfirmDestructiveAction:
            return "Confirmar accion destructiva"
        case .settingsClearMeetingHistoryMessage:
            return "Esto eliminara permanentemente todas las reuniones guardadas, notas, transcripciones y grabaciones de audio retenidas. Esta accion no se puede deshacer."
        case .settingsTranscriptionSection:
            return "Transcripcion"
        case .settingsDictationModel:
            return "Modelo de dictado"
        case .settingsCohereLanguage:
            return "Idioma de Cohere"
        case .settingsAiTranscriptCleanup:
            return "Limpieza IA de transcripcion"
        case .settingsCleanupModel:
            return "Modelo de limpieza"
        case .settingsDownloadCleanupModelHint:
            return "Descarga un modelo de limpieza en Modelos"
        case .settingsAppContext:
            return "Contexto de la app"
        case .settingsSharedContextDescription:
            return "Usa texto cercano de otras apps para limpiar dictados y resumir reuniones, ademas de OCR para reuniones cuando esta disponible. Todo el procesamiento se mantiene en el dispositivo."
        case .settingsMeetingTranscriptionSection:
            return "Transcripcion de reuniones"
        case .settingsMeetingModel:
            return "Modelo de reuniones"
        case .settingsLiveMeetingTranscript:
            return "Transcript en vivo"
        case .settingsMeetingContext:
            return "Contexto de reuniones"
        case .settingsMeetingSummariesSection:
            return "Resumenes de reuniones"
        case .settingsSummaryBackend:
            return "Motor de resumen"
        case .settingsAccount:
            return "Cuenta"
        case .settingsModel:
            return "Modelo"
        case .settingsFreeModel:
            return "Modelo gratuito"
        case .settingsCustomModelID:
            return "ID de modelo personalizado"
        case .settingsApiKey:
            return "Clave API"
        case .settingsDefaultTemplate:
            return "Plantilla por defecto"
        case .settingsTemplates:
            return "Plantillas"
        case .settingsRecordingSection:
            return "Grabacion"
        case .settingsAutoRecordCalendarMeetings:
            return "Grabar automaticamente reuniones del calendario"
        case .settingsAutoRecordQuickNotes:
            return "Grabar automaticamente Quick Notes"
        case .settingsNotifyWhenMeetingDetected:
            return "Avisar al detectar una reunion"
        case .settingsSaveMeetingRecording:
            return "Guardar grabacion de la reunion"
        case .settingsAdvancedSection:
            return "Avanzado"
        case .settingsEnablePostMeetingHook:
            return "Activar hook post-reunion"
        case .settingsHookScript:
            return "Script del hook"
        case .settingsTimeout:
            return "Tiempo limite"
        case .settingsSeconds(let count):
            return "\(count) segundos"
        case .settingsAdvancedHookDescription:
            return "Avanzado: ejecuta un binario indicado por el usuario al terminar cada reunion. El ejecutable recibe JSON por stdin y debe poder ejecutarse por si solo."
        case .settingsCalendarSection:
            return "Calendario"
        case .settingsGoogleCalendar:
            return "Google Calendar"
        case .settingsLocalCalendars:
            return "Calendarios locales"
        case .settingsLocalCalendarsHint:
            return "Elige que calendarios de macOS debe usar Muesli para proximas reuniones, avisos y deteccion."
        case .settingsNoLocalCalendarsFound:
            return "No se encontraron calendarios locales."
        case .settingsGoogleCalendarUnavailable:
            return "Las credenciales de Google Calendar no estan configuradas."
        case .settingsFloatingIndicatorSection:
            return "Indicador flotante"
        case .settingsShowFloatingIndicator:
            return "Mostrar indicador flotante"
        case .settingsIndicatorPosition:
            return "Posicion del indicador"
        case .settingsAppearanceSection:
            return "Apariencia"
        case .settingsTheme:
            return "Tema"
        case .settingsDarkMode:
            return "Modo oscuro"
        case .settingsMenuBarIcon:
            return "Icono de la barra de menu"
        case .settingsAccentColor:
            return "Color de acento"
        case .settingsPlaySoundEffects:
            return "Reproducir efectos de sonido"
        case .settingsShowNextMeetingInMenuBar:
            return "Mostrar siguiente reunion en la barra de menu"
        case .settingsMaraudersMapSection:
            return "Mapa del Merodeador"
        case .settingsMeetingCountdownAudio:
            return "Audio de cuenta atras de la reunion"
        case .settingsMischiefManaged:
            return "Travesura realizada"
        case .settingsSignedInSignOut:
            return "Sesion iniciada · Cerrar sesion"
        case .settingsSigningIn:
            return "Iniciando sesion..."
        case .settingsSignInWithChatGPT:
            return "Iniciar sesion con ChatGPT"
        case .settingsConnectedDisconnect:
            return "Conectado · Desconectar"
        case .settingsConnecting:
            return "Conectando..."
        case .settingsConnectGoogleCalendar:
            return "Conectar Google Calendar"
        case .settingsGoogleOAuthPending:
            return "Verificacion de Google OAuth pendiente"
        case .settingsChooseAudioClip:
            return "Elegir un clip de audio"
        case .settingsChooseHookScriptTitle:
            return "Elegir un script de hook"
        case .settingsChooseScriptPrompt:
            return "Elegir script"
        case .settingsChooseScriptEllipsis:
            return "Elegir un script..."
        case .settingsNoHookScriptSelected:
            return "No hay script de hook seleccionado"
        case .settingsClearHookScript:
            return "Borrar script de hook"
        case .settingsChooseHookScript:
            return "Elegir script de hook"
        case .settingsNoApiKeyConfigured:
            return "No hay clave API configurada"
        case .settingsApiKeyConfigured:
            return "Clave configurada"
        case .settingsLoadingModels:
            return "Cargando modelos"
        case .settingsLoadModels:
            return "Cargar"
        case .quickNoteButton:
            return "Nota rápida"
        case .quickNoteButtonShort:
            return "Nota"
        case .quickNoteButtonHelp:
            return "Crear una nota rapida de reunion"
        case .titlebarToggleSidebarHelp:
            return "Mostrar u ocultar barra lateral"
        case .settingsRecordingSaveNever:
            return "Nunca"
        case .settingsRecordingSavePrompt:
            return "Preguntar siempre"
        case .settingsRecordingSaveAlways:
            return "Siempre"
        case .settingsDefaultTemplateAuto:
            return "Auto"
        case .settingsCustomIndicatorPosition:
            return "Personalizada (arrastra para recolocar)"
        case .settingsThemeWarm:
            return "Warm"
        case .settingsThemeNeutral:
            return "Neutral"
        case .settingsThemeGraphite:
            return "Graphite"
        case .dictationsNoDictationsTitle:
            return "Aun no hay dictados"
        case .dictationsHoldToStart(let hotkey):
            return "Mantén \(hotkey) para empezar a dictar"
        case .dictationsTodayHeader:
            return "HOY"
        case .dictationsYesterdayHeader:
            return "AYER"
        case .dictationsCopy:
            return "Copiar"
        case .dictationsDeleteTitle:
            return "Eliminar dictado"
        case .dictationsDeleteMessage:
            return "Seguro que quieres eliminar este dictado? Esta accion no se puede deshacer."
        case .dictionaryTitle:
            return "Diccionario"
        case .dictionaryAddNew:
            return "Anadir nuevo"
        case .dictionaryDescription:
            return "Anade palabras personalizadas para nombres, marcas y terminos de tu dominio, y ajusta lo agresivo que debe ser cada coincidencia difusa frente a errores de transcripcion."
        case .dictionaryEmptyTitle:
            return "Aun no hay palabras personalizadas"
        case .dictionaryEmptyMessage:
            return "Anade palabras que la transcripcion suele escribir mal"
        case .dictionaryWordPlaceholder:
            return "Palabra"
        case .dictionaryReplacementPlaceholder:
            return "Reemplazar por (opcional)"
        case .dictionaryMatchingThreshold:
            return "Umbral de coincidencia"
        case .dictionaryAdd:
            return "Anadir"
        case .dictionarySave:
            return "Guardar"
        case .shortcutsTitle:
            return "Atajos"
        case .syncTitle:
            return "Sincronización"
        case .shortcutsDescription:
            return "Elige tu atajo preferido para dictado."
        case .shortcutsPushToTalk:
            return "Pulsar para hablar"
        case .shortcutsPushToTalkHint:
            return "Mantén pulsado para grabar y suelta para transcribir"
        case .shortcutsPressModifier:
            return "Pulsa una tecla modificadora..."
        case .shortcutsChangeShortcut:
            return "Cambiar atajo"
        case .shortcutsHandsFreeMode:
            return "Modo manos libres"
        case .shortcutsHandsFreeHint:
            return "Doble pulsacion para empezar, otra pulsacion para parar"
        case .shortcutsResetDefault:
            return "Restablecer por defecto"
        case .aboutTitle:
            return "Acerca de"
        case .aboutAppInfoSection:
            return "Info de la app"
        case .aboutVersion:
            return "Version"
        case .aboutCheckForUpdates:
            return "Buscar actualizaciones"
        case .aboutCheckNow:
            return "Buscar ahora"
        case .aboutSupportSection:
            return "Soporte"
        case .aboutSupportDevelopment:
            return "Apoyar el desarrollo"
        case .aboutDonate:
            return "Donar"
        case .aboutSourceCode:
            return "Codigo fuente"
        case .aboutViewOnGitHub:
            return "Ver en GitHub"
        case .aboutDataSection:
            return "Datos"
        case .aboutAppDataDirectory:
            return "Directorio de datos de la app"
        case .aboutOpen:
            return "Abrir"
        case .aboutAcknowledgementsSection:
            return "Agradecimientos"
        case .aboutInstallUpdate:
            return "Instalar actualizacion"
        case .aboutTryAgain:
            return "Reintentar"
        case .aboutCheckingForUpdatesTitle:
            return "Buscando actualizaciones"
        case .aboutCheckingForUpdatesMessage:
            return "Muesli esta consultando el appcast para la version mas reciente."
        case .aboutUpdaterBusyTitle:
            return "El actualizador esta ocupado"
        case .aboutUpdateAvailableTitle(let version):
            return "Muesli \(version) esta disponible"
        case .aboutUpdateAvailableMessage:
            return "Hay una actualizacion disponible. Inicia el actualizador para descargarla e instalarla."
        case .aboutUpdateReadyTitle(let version):
            return "Muesli \(version) esta lista para instalar"
        case .aboutUpdateReadyMessage:
            return "Cierra y vuelve a abrir Muesli para terminar de instalar la actualizacion."
        case .aboutInstallingUpdateTitle(let version):
            return "Instalando Muesli \(version)"
        case .aboutInstallingUpdateMessage:
            return "Sparkle esta preparando la actualizacion. Muesli puede reiniciarse cuando termine la instalacion."
        case .aboutUpToDateTitle:
            return "Muesli esta al dia"
        case .aboutUpToDateMessage:
            return "No se encontro una version mas reciente en el appcast."
        case .aboutUpdatesDisabledTitle:
            return "Las actualizaciones estan desactivadas"
        case .aboutUpdateCheckFailedTitle:
            return "Fallo la comprobacion de actualizaciones"
        case .statsDayStreak:
            return "dias seguidos"
        case .statsWordsDictated:
            return "palabras dictadas"
        case .statsAvgWPM:
            return "ppm medias"
        case .statsMeetings:
            return "reuniones"
        case .templateManagerIcon:
            return "Icono"
        case .templateManagerNamePlaceholder:
            return "Seguimiento con cliente"
        case .statusLabel(let text):
            return "Estado: \(text)"
        case .statusIdle:
            return "En espera"
        case .statusOpenApp(let name):
            return "Abrir \(name)"
        case .statusStopMeetingRecording:
            return "Detener grabacion de reunion"
        case .statusStartMeetingRecording:
            return "Iniciar grabacion de reunion"
        case .statusDiscardMeetingRecording:
            return "Descartar grabacion de reunion..."
        case .statusRecentDictations:
            return "Dictados recientes"
        case .statusNoDictationsYet:
            return "Aun no hay dictados"
        case .statusTranscriptionBackend:
            return "Motor de transcripcion"
        case .statusMeetingsBackend:
            return "Motor de reuniones"
        case .statusSettings:
            return "Ajustes..."
        case .statusCheckForUpdates:
            return "Buscar actualizaciones..."
        case .statusQuit:
            return "Salir"
        case .statusStartsIn(let value):
            return "Empieza en \(value)"
        case .commonOK:
            return "Aceptar"
        }
    }
}
