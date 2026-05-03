import SwiftUI
import MuesliCore

struct DashboardRootView: View {
    let appState: AppState
    let controller: MuesliController

    private var showsMeetingsToolbarActions: Bool {
        guard !appState.isSearchActive, appState.selectedTab == .meetings else { return false }
        return true
    }

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
        .toolbar {
            if showsMeetingsToolbarActions {
                ToolbarItem(placement: .automatic) {
                    quickNoteToolbarButton
                }
            }
        }
    }

    private var quickNoteToolbarButton: some View {
        let language = AppLanguage.resolved(appState.config.appLanguage)
        let isDisabled = appState.isMeetingRecording
        return Button {
            controller.startQuickNoteMeeting()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text(L10n.text(.quickNoteButton, language: language))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isDisabled ? MuesliTheme.textTertiary : MuesliTheme.accent)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .fill(isDisabled ? MuesliTheme.surfacePrimary : MuesliTheme.accent.opacity(0.14))
            )
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(
                        isDisabled ? MuesliTheme.surfaceBorder : MuesliTheme.accent.opacity(0.35),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(L10n.text(.quickNoteButtonHelp, language: language))
    }
}
