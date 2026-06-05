import MuesliCore

enum MeetingChatMountPolicy {
    static func showsFolderChat(
        selectedFolderID: Int64?,
        isSearchActive: Bool,
        navigationState: MeetingsNavigationState
    ) -> Bool {
        selectedFolderID != nil && !isSearchActive && navigationState == .browser
    }

    static func showsMeetingChat(for meeting: MeetingRecord?) -> Bool {
        guard let meeting else { return false }
        return meeting.status == .completed
    }
}
