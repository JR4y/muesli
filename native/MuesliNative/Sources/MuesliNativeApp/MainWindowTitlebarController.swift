import AppKit
import SwiftUI
import MuesliCore

@MainActor
final class MainWindowTitlebarController {
    private weak var window: NSWindow?
    private let appState: AppState
    private let controller: MuesliController
    private var leadingAccessory: NSTitlebarAccessoryViewController?
    private var trailingAccessory: NSTitlebarAccessoryViewController?

    init(appState: AppState, controller: MuesliController) {
        self.appState = appState
        self.controller = controller
    }

    nonisolated static func showsQuickNoteAccessory(isSearchActive: Bool, selectedTab: DashboardTab) -> Bool {
        DashboardRootView.showsQuickNoteTitlebarControl(
            isSearchActive: isSearchActive,
            selectedTab: selectedTab
        )
    }

    nonisolated static func usesCompactQuickNoteLayout(availableWidth: CGFloat) -> Bool {
        availableWidth < 140
    }

    func install(on window: NSWindow) {
        self.window = window
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        installLeadingAccessory(on: window)
        installTrailingAccessory(on: window)
    }

    private func installLeadingAccessory(on window: NSWindow) {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .left
        accessory.fullScreenMinHeight = 36
        accessory.view = NSHostingView(
            rootView: TitlebarSidebarToggleButton(appState: appState)
        )
        leadingAccessory = accessory
        window.addTitlebarAccessoryViewController(accessory)
    }

    private func installTrailingAccessory(on window: NSWindow) {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        accessory.fullScreenMinHeight = 36
        accessory.view = NSHostingView(
            rootView: TitlebarQuickNoteButton(
                appState: appState,
                controller: controller,
                compact: Self.usesCompactQuickNoteLayout(availableWidth: window.frame.width)
            )
        )
        trailingAccessory = accessory
        window.addTitlebarAccessoryViewController(accessory)
    }
}

private struct TitlebarSidebarToggleButton: View {
    let appState: AppState

    var body: some View {
        Button {
            appState.isSidebarVisible.toggle()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MuesliTheme.textSecondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(MuesliTheme.backgroundRaised))
                .overlay(
                    Circle()
                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(L10n.text(.titlebarToggleSidebarHelp, config: appState.config))
        .padding(.leading, 6)
    }
}

private struct TitlebarQuickNoteButton: View {
    let appState: AppState
    let controller: MuesliController
    let compact: Bool

    private var isVisible: Bool {
        MainWindowTitlebarController.showsQuickNoteAccessory(
            isSearchActive: appState.isSearchActive,
            selectedTab: appState.selectedTab
        )
    }

    private var isDisabled: Bool {
        appState.isMeetingRecording
    }

    var body: some View {
        Group {
            if isVisible {
                Button {
                    controller.startQuickNoteMeeting()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        if !compact {
                            Text(L10n.text(.quickNoteButton, config: appState.config))
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(isDisabled ? MuesliTheme.textTertiary : MuesliTheme.accent)
                    .padding(.horizontal, compact ? 10 : MuesliTheme.spacing12)
                    .frame(height: 30)
                    .background(
                        Capsule().fill(
                            isDisabled ? MuesliTheme.surfacePrimary.opacity(0.6) : MuesliTheme.accentSubtle
                        )
                    )
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
                .help(L10n.text(.quickNoteButtonHelp, config: appState.config))
                .padding(.trailing, 6)
            } else {
                Color.clear
                    .frame(width: 0, height: 0)
            }
        }
    }
}
