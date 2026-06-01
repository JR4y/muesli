import AppKit
import SwiftUI
import MuesliCore

struct DashboardRootView: View {
    private static let customTopBarHeight: CGFloat = 54

    let appState: AppState
    let controller: MuesliController

    static func showsQuickNoteTitlebarControl(isSearchActive: Bool, selectedTab: DashboardTab) -> Bool {
        guard !isSearchActive, selectedTab == .meetings else { return false }
        return true
    }

    private var showsQuickNoteTopBar: Bool {
        Self.showsQuickNoteTitlebarControl(
            isSearchActive: appState.isSearchActive,
            selectedTab: appState.selectedTab
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            splitViewContent
                .padding(.top, showsQuickNoteTopBar ? Self.customTopBarHeight : 0)

            if showsQuickNoteTopBar {
                customTopBar
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(MuesliTheme.backgroundBase)
        .preferredColorScheme(appState.config.darkMode ? .dark : .light)
    }

    private var splitViewContent: some View {
        NavigationSplitView {
            SidebarView(appState: appState, controller: controller)
                .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 300)
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MuesliTheme.backgroundBase)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var customTopBar: some View {
        HStack(spacing: MuesliTheme.spacing12) {
            topBarIconButton(
                systemImage: "sidebar.left",
                help: "Toggle sidebar",
                action: toggleSidebar
            )
            Spacer(minLength: MuesliTheme.spacing16)
            quickNoteTopBarButton
        }
        .padding(.horizontal, MuesliTheme.spacing16)
        .padding(.top, MuesliTheme.spacing8)
        .padding(.bottom, MuesliTheme.spacing8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(MuesliTheme.backgroundBase)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MuesliTheme.surfaceBorder)
                .frame(height: 1)
        }
    }

    private var quickNoteTopBarButton: some View {
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
            .frame(height: 32)
            .background(Capsule().fill(isDisabled ? MuesliTheme.surfacePrimary.opacity(0.6) : MuesliTheme.accentSubtle))
            .clipShape(Capsule())
            .overlay(
                Capsule()
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

    private func topBarIconButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MuesliTheme.textSecondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(MuesliTheme.backgroundRaised))
                .overlay(
                    Circle()
                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func toggleSidebar() {
        let action = #selector(NSSplitViewController.toggleSidebar(_:))
        if NSApp.sendAction(action, to: nil, from: nil) {
            return
        }
        NSApp.keyWindow?.firstResponder?.tryToPerform(action, with: nil)
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
