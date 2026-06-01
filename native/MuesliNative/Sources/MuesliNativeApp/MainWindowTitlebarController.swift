import AppKit
import SwiftUI
import MuesliCore

@MainActor
final class MainWindowTitlebarController {
    struct QuickNoteAccessoryMetrics: Equatable {
        let accessorySize: CGSize
        let controlHeight: CGFloat
        let showsLabel: Bool
        let trailingPadding: CGFloat
    }

    nonisolated private static let sidebarAccessorySize = CGSize(width: 58, height: 40)
    nonisolated private static let compactQuickNoteAccessorySize = CGSize(width: 52, height: 40)
    nonisolated private static let fullQuickNoteAccessorySize = CGSize(width: 92, height: 40)

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
        availableWidth < 760
    }

    nonisolated static func quickNoteAccessoryMetrics(availableWidth: CGFloat) -> QuickNoteAccessoryMetrics {
        let compact = usesCompactQuickNoteLayout(availableWidth: availableWidth)
        return QuickNoteAccessoryMetrics(
            accessorySize: compact ? compactQuickNoteAccessorySize : fullQuickNoteAccessorySize,
            controlHeight: 26,
            showsLabel: !compact,
            trailingPadding: compact ? 10 : 12
        )
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
        accessory.fullScreenMinHeight = Self.sidebarAccessorySize.height
        accessory.view = hostingAccessoryView(
            rootView: TitlebarSidebarToggleButton(appState: appState),
            size: Self.sidebarAccessorySize
        )
        leadingAccessory = accessory
        window.addTitlebarAccessoryViewController(accessory)
    }

    private func installTrailingAccessory(on window: NSWindow) {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        let metrics = Self.quickNoteAccessoryMetrics(availableWidth: window.frame.width)
        accessory.view = hostingAccessoryView(
            rootView: TitlebarQuickNoteButton(
                appState: appState,
                controller: controller,
                metrics: metrics
            ),
            size: metrics.accessorySize
        )
        trailingAccessory = accessory
        window.addTitlebarAccessoryViewController(accessory)
    }

    private func hostingAccessoryView<Content: View>(rootView: Content, size: CGSize) -> NSView {
        let hostingView = NSHostingView(
            rootView: rootView
                .frame(width: size.width, height: size.height, alignment: .center)
        )
        hostingView.frame = NSRect(origin: .zero, size: size)
        return hostingView
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.leading, 12)
    }
}

private struct TitlebarQuickNoteButton: View {
    let appState: AppState
    let controller: MuesliController
    let metrics: MainWindowTitlebarController.QuickNoteAccessoryMetrics

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
                        if metrics.showsLabel {
                            Text(L10n.text(.quickNoteButtonShort, config: appState.config))
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(isDisabled ? MuesliTheme.textTertiary : MuesliTheme.accent)
                    .padding(.horizontal, metrics.showsLabel ? 10 : 8)
                    .frame(height: metrics.controlHeight)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.trailing, metrics.trailingPadding)
            } else {
                Color.clear
                    .frame(width: 0, height: 0)
            }
        }
    }
}
