import Foundation
import Observation
import MuesliCore

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
    case dictation
    case computerUse
    case meetings
    case appearance
    case dictionary
    case models
    case shortcuts
    case sync

    var id: String { rawValue }
}

enum MeetingsNavigationState: Equatable {
    case browser
    case document(Int64)
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

enum UserInitiatedUpdateAction: Equatable {
    case presentStandardUpdater
    case showBusy(message: String)
}

enum UpdateInteractionPolicy {
    static let busyMessage = "Sparkle is still finishing the previous update check. Try again in a moment."

    static func installAction(for status: SparkleUpdateStatus) -> UserInitiatedUpdateAction {
        switch status {
        case .checking, .busy, .installing:
            return .showBusy(message: busyMessage)
        case .idle, .available, .downloaded, .upToDate, .disabled, .failed:
            return .presentStandardUpdater
        }
    }
}

@MainActor
@Observable
final class AppState {
    // Dashboard data
    var dictationRows: [DictationRecord] = []
    var meetingRows: [MeetingRecord] = []
    var totalMeetingCount: Int = 0
    var meetingCountsByFolder: [Int64: Int] = [:]
    var selectedMeetingID: Int64?
    var selectedMeetingRecord: MeetingRecord?
    var folders: [MeetingFolder] = []
    var selectedFolderID: Int64?  // nil = "All Meetings"
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
    var dictationState: DictationState = .idle
    var isVoiceNoteRecording: Bool = false
    var isChatGPTAuthenticated: Bool = false
    var isGoogleCalendarAvailable: Bool = false
    var isGoogleCalendarVerified: Bool = false
    var isGoogleCalendarAuthenticated: Bool = false
    var availableLocalCalendars: [LocalCalendarInfo] = []
    var upcomingCalendarEvents: [UnifiedCalendarEvent] = []
    var hiddenCalendarEventIDs: Set<String> = []
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

    func folder(id: Int64?) -> MeetingFolder? {
        guard let id else { return nil }
        return folders.first(where: { $0.id == id })
    }

    func childFolders(of parentFolderID: Int64?) -> [MeetingFolder] {
        folders.filter { $0.parentFolderID == parentFolderID }
    }

    func hasChildFolders(_ folderID: Int64) -> Bool {
        folders.contains(where: { $0.parentFolderID == folderID })
    }

    func descendantFolderIDs(of folderID: Int64) -> Set<Int64> {
        var descendants = Set<Int64>()
        var pending = [folderID]
        while let next = pending.popLast() {
            for child in childFolders(of: next) where descendants.insert(child.id).inserted {
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
}
