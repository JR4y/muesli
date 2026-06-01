import SwiftUI
import MuesliCore

struct DashboardRootView: View {
    nonisolated private static let meetingsTitlebarContentInset: CGFloat = 36

    let appState: AppState
    let controller: MuesliController

    nonisolated static func showsQuickNoteTitlebarControl(isSearchActive: Bool, selectedTab: DashboardTab) -> Bool {
        guard !isSearchActive, selectedTab == .meetings else { return false }
        return true
    }

    nonisolated static func titlebarContentInset(isSearchActive: Bool, selectedTab: DashboardTab) -> CGFloat {
        showsQuickNoteTitlebarControl(isSearchActive: isSearchActive, selectedTab: selectedTab)
            ? meetingsTitlebarContentInset
            : 0
    }

    var body: some View {
        DashboardSplitShell(
            isSidebarVisible: Binding(
                get: { appState.isSidebarVisible },
                set: { appState.isSidebarVisible = $0 }
            )
        ) {
            SidebarView(appState: appState, controller: controller)
        } detail: {
            detailContent
                .padding(.top, detailTopInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MuesliTheme.backgroundBase)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(MuesliTheme.backgroundBase)
        .preferredColorScheme(appState.config.darkMode ? .dark : .light)
    }

    private var detailTopInset: CGFloat {
        Self.titlebarContentInset(
            isSearchActive: appState.isSearchActive,
            selectedTab: appState.selectedTab
        )
    }

    @ViewBuilder
    private var detailContent: some View {
        if appState.isSearchActive,
           case .document(let id) = appState.meetingsNavigationState {
            MeetingDetailView(
                meeting: appState.selectedMeeting,
                controller: controller,
                appState: appState,
                onBack: {
                    appState.meetingsNavigationState = .browser
                    appState.selectedMeetingID = nil
                    appState.selectedMeetingRecord = nil
                },
                backLabel: "Back to Search"
            )
            .id(id)
        } else if appState.isSearchActive {
            SearchResultsView(appState: appState, controller: controller)
        } else {
            switch appState.selectedTab {
            case .dictations:
                DictationsView(appState: appState, controller: controller)
            case .meetings:
                MeetingsView(appState: appState, controller: controller)
            case .dictionary:
                DictionaryView(appState: appState, controller: controller)
            case .models:
                ModelsView(appState: appState, controller: controller)
            case .shortcuts:
                ShortcutsView(appState: appState, controller: controller)
            case .settings:
                SettingsView(appState: appState, controller: controller)
            case .about:
                AboutView(appState: appState)
            }
        }
    }
}
