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
    case sidebarFolderName
    case sidebarNewFolder
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
    case meetingsCalendarSyncHint
    case meetingsJoinAndRecord
    case meetingsAddToFolder
    case meetingsHideFromComingUp
    case meetingsCount(count: Int)
    case meetingsHeaderHint
    case meetingsManageTemplates
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
    case meetingSummarizing
    case meetingDone
    case meetingEdit
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
    case settingsTitle
    case settingsPaneGeneral
    case settingsPaneDictation
    case settingsPaneMeetings
    case settingsPaneAppearance
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
    case settingsMeetingContext
    case settingsMeetingSummariesSection
    case settingsSummaryBackend
    case settingsAccount
    case settingsModel
    case settingsApiKey
    case settingsDefaultTemplate
    case settingsTemplates
    case settingsRecordingSection
    case settingsAutoRecordCalendarMeetings
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
        case .sidebarFolderName:
            return "Folder name"
        case .sidebarNewFolder:
            return "New Folder"
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
        case .meetingsCalendarSyncHint:
            return "Add Google to macOS Calendar for real-time sync"
        case .meetingsJoinAndRecord:
            return "Join & Record"
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
        case .meetingSummarizing:
            return "Summarizing..."
        case .meetingDone:
            return "Done"
        case .meetingEdit:
            return "Edit"
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
        case .settingsTitle:
            return "Settings"
        case .settingsPaneGeneral:
            return "General"
        case .settingsPaneDictation:
            return "Dictation"
        case .settingsPaneMeetings:
            return "Meetings"
        case .settingsPaneAppearance:
            return "Appearance"
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
        case .sidebarFolderName:
            return "Nombre de la carpeta"
        case .sidebarNewFolder:
            return "Nueva carpeta"
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
        case .meetingsCalendarSyncHint:
            return "Agrega Google al Calendario de macOS para sincronizacion en tiempo real"
        case .meetingsJoinAndRecord:
            return "Entrar y grabar"
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
        case .meetingSummarizing:
            return "Resumiendo..."
        case .meetingDone:
            return "Listo"
        case .meetingEdit:
            return "Editar"
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
        case .settingsTitle:
            return "Ajustes"
        case .settingsPaneGeneral:
            return "General"
        case .settingsPaneDictation:
            return "Dictado"
        case .settingsPaneMeetings:
            return "Reuniones"
        case .settingsPaneAppearance:
            return "Apariencia"
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
