import Foundation
import Observation
import MuesliCore
import MuesliMeetingChat

enum DashboardTab: String, CaseIterable {
    case dictations
    case meetings
    case dictionary
    case models
    case shortcuts
    case settings
    case about
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case voiceAndDictation
    case meetings
    case models
    case appearance

    static let allCases: [SettingsPane] = [
        .general,
        .voiceAndDictation,
        .meetings,
        .models,
        .appearance,
    ]

    var id: String { rawValue }

    func localizedTitle(config: AppConfig) -> String {
        switch self {
        case .general:
            return L10n.text(.settingsPaneGeneral, config: config)
        case .voiceAndDictation:
            return L10n.text(.settingsPaneVoiceAndDictation, config: config)
        case .meetings:
            return L10n.text(.settingsPaneMeetings, config: config)
        case .models:
            return L10n.text(.sidebarModels, config: config)
        case .appearance:
            return L10n.text(.settingsPaneAppearance, config: config)
        }
    }
}

enum MeetingsNavigationState: Equatable {
    case browser
    case document(Int64)
}

enum MeetingBrowserMode: Equatable {
    case active
    case archive

    var archiveFilter: MeetingArchiveFilter {
        switch self {
        case .active: return .active
        case .archive: return .archived
        }
    }
}

enum SparkleUpdateStatus: Equatable {
    case idle
    case checking
    case busy(message: String)
    case available(version: String)
    case downloaded(version: String)
    case installing(version: String)
    case upToDate
    case disabled(message: String)
    case failed(message: String)
}

enum GoogleCalendarListLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

@MainActor
@Observable
final class AppState {
    @ObservationIgnored var meetingChatStore: (any MeetingChatStoring)?

    // Dashboard data
    var dictationRows: [DictationRecord] = []
    var meetingRows: [MeetingRecord] = []
    var totalMeetingCount: Int = 0
    var archivedMeetingCount: Int = 0
    var meetingCountsByFolder: [Int64: Int] = [:]
    var archivedMeetingCountsByFolder: [Int64: Int] = [:]
    var selectedMeetingID: Int64?
    var selectedMeetingRecord: MeetingRecord?
    var folders: [MeetingFolder] = []
    var archivedFolders: [MeetingFolder] = []
    var selectedFolderID: Int64?  // nil = "All Meetings"
    var meetingBrowserMode: MeetingBrowserMode = .active
    var meetingsNavigationState: MeetingsNavigationState = .browser
    var isMeetingTemplatesManagerPresented: Bool = false
    var dictationStats: DictationStats = DictationStats(
        totalWords: 0, totalSessions: 0, averageWordsPerSession: 0,
        averageWPM: 0, currentStreakDays: 0, longestStreakDays: 0
    )
    var meetingStats: MeetingStats = MeetingStats(totalWords: 0, totalMeetings: 0, averageWPM: 0)

    // Config-driven state
    var selectedBackend: BackendOption = .whisper
    var selectedMeetingTranscriptionBackend: BackendOption = .whisper
    var selectedMeetingSummaryBackend: MeetingSummaryBackendOption = .chatGPT
    var activePostProcessor: PostProcessorOption = PostProcessorOption.defaultOption
    var config: AppConfig = AppConfig()
    var launchAtLoginRegistrationState: LaunchAtLoginRegistrationState = .disabled

    // Live status
    var isMeetingRecording: Bool = false
    var isMeetingRecordingPaused: Bool = false
    var isMeetingStarting: Bool = false
    var meetingStartStatus: String?
    var dictationState: DictationState = .idle
    var isVoiceNoteRecording: Bool = false
    var isChatGPTAuthenticated: Bool = false
    var isGoogleCalendarAvailable: Bool = false
    var isGoogleCalendarVerified: Bool = false
    var isGoogleCalendarAuthenticated: Bool = false
    var availableLocalCalendars: [LocalCalendarInfo] = []
    var upcomingCalendarEvents: [UnifiedCalendarEvent] = []
    var hiddenCalendarEventIDs: Set<String> = []
    var availableEventKitCalendars: [AvailableCalendar] = []
    var availableGoogleCalendars: [GoogleCalendarSummary] = []
    var googleCalendarListLoadState: GoogleCalendarListLoadState = .idle
    var sparkleUpdateStatus: SparkleUpdateStatus = .idle
    var sparkleLastCheckedAt: Date?
    var modelPreparationTitle: String?
    var modelPreparationDetail: String?
    var modelPreparationProgress: Double?
    var isModelPreparingAfterDownload: Bool = false
    var modelPreparationIsComplete: Bool = false
    var activeMeetingTranscriptMeetingID: Int64?
    var activeMeetingTranscriptTurns: [LiveMeetingTranscriptTurn] = []

    // Dictation pagination & filtering
    var dictationPageSize: Int = 50
    var dictationFromDate: String? = nil
    var dictationToDate: String? = nil
    var hasMoreDictations: Bool = true

    // Search
    var searchQuery: String = ""
    var searchResultDictations: [DictationRecord] = []
    var searchResultMeetings: [MeetingRecord] = []
    var focusSearchField: Bool = false
    var isSearchActive: Bool { !searchQuery.isEmpty }

    // Navigation
    var selectedTab: DashboardTab = .meetings
    var selectedSettingsPane: SettingsPane = .general
    var isSidebarVisible: Bool = true

    // Supabase sync
    var supabaseSyncConfigured: Bool = false
    var isSupabaseAuthenticated: Bool = false
    var supabaseEmail: String?
    var supabaseSyncStatusText: String = ""
    var supabaseSyncErrorText: String?
    var supabaseLastSyncAt: Date?
    var supabaseAwaitingEmailConfirmation: Bool = false
    var syncedFolderCount: Int = 0
    var syncedDictationCount: Int = 0
    var syncedMeetingCount: Int = 0

    // Computed
    var selectedMeeting: MeetingRecord? {
        guard let id = selectedMeetingID else { return nil }
        if let row = meetingRows.first(where: { $0.id == id }) {
            return row
        }
        guard selectedMeetingRecord?.id == id else { return nil }
        return selectedMeetingRecord
    }

    var selectedFolder: MeetingFolder? {
        guard let selectedFolderID else { return nil }
        return folder(id: selectedFolderID)
    }

    var browserFolders: [MeetingFolder] {
        meetingBrowserMode == .archive ? archivedFolders : folders
    }

    var browserMeetingCountsByFolder: [Int64: Int] {
        meetingBrowserMode == .archive ? archivedMeetingCountsByFolder : meetingCountsByFolder
    }

    func folder(id: Int64?) -> MeetingFolder? {
        guard let id else { return nil }
        return browserFolders.first(where: { $0.id == id })
    }

    func childFolders(of parentFolderID: Int64?, includeArchived: Bool? = nil) -> [MeetingFolder] {
        folders(forArchiveMode: includeArchived).filter { $0.parentFolderID == parentFolderID }
    }

    func hasChildFolders(_ folderID: Int64, includeArchived: Bool? = nil) -> Bool {
        folders(forArchiveMode: includeArchived).contains(where: { $0.parentFolderID == folderID })
    }

    func descendantFolderIDs(of folderID: Int64, includeArchived: Bool? = nil) -> Set<Int64> {
        var descendants = Set<Int64>()
        var pending = [folderID]
        while let next = pending.popLast() {
            for child in childFolders(of: next, includeArchived: includeArchived) where descendants.insert(child.id).inserted {
                pending.append(child.id)
            }
        }
        return descendants
    }

    func folderPath(for folderID: Int64, separator: String = " / ") -> String {
        guard let folder = folder(id: folderID) else { return "" }
        var names = [folder.name]
        var currentParentID = folder.parentFolderID
        while let parent = self.folder(id: currentParentID) {
            names.append(parent.name)
            currentParentID = parent.parentFolderID
        }
        return names.reversed().joined(separator: separator)
    }

    func folders(forArchiveMode includeArchived: Bool? = nil) -> [MeetingFolder] {
        let archiveMode = includeArchived ?? (meetingBrowserMode == .archive)
        return archiveMode ? archivedFolders : folders
    }
}
