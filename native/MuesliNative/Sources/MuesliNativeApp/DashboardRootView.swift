import SwiftUI
import MuesliCore

struct DashboardRootView: View {
    let appState: AppState
    let controller: MuesliController

    var body: some View {
        NavigationSplitView {
            SidebarView(appState: appState, controller: controller)
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 300)
        } detail: {
            Group {
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
                        SettingsView(appState: appState, controller: controller)
                            .onAppear {
                                appState.selectedSettingsPane = .dictionary
                                appState.selectedTab = .settings
                            }
                    case .models:
                        SettingsView(appState: appState, controller: controller)
                            .onAppear {
                                appState.selectedSettingsPane = .models
                                appState.selectedTab = .settings
                            }
                    case .shortcuts:
                        SettingsView(appState: appState, controller: controller)
                            .onAppear {
                                appState.selectedSettingsPane = .shortcuts
                                appState.selectedTab = .settings
                            }
                    case .settings:
                        SettingsView(appState: appState, controller: controller)
                    case .about:
                        AboutView(appState: appState, controller: controller)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MuesliTheme.backgroundBase)
        }
        .frame(minWidth: 900, minHeight: 600)
        .preferredColorScheme(appState.config.darkMode ? .dark : .light)
    }
}
