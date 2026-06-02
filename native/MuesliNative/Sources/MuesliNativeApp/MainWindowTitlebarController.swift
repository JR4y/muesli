import AppKit
import SwiftUI
import MuesliCore

@MainActor
final class MainWindowTitlebarController {
    nonisolated private static let sidebarAccessorySize = CGSize(width: 58, height: 40)

    private weak var window: NSWindow?
    private let appState: AppState
    private var leadingAccessory: NSTitlebarAccessoryViewController?

    init(appState: AppState, controller _: MuesliController) {
        self.appState = appState
    }

    func install(on window: NSWindow) {
        self.window = window
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        installLeadingAccessory(on: window)
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
