import CoreGraphics
import Testing
@testable import MuesliNativeApp

@Suite("Main window titlebar controller")
struct MainWindowTitlebarControllerTests {
    @Test("quick note accessory uses the compact variant below the width threshold")
    func compactQuickNoteThreshold() {
        #expect(MainWindowTitlebarController.usesCompactQuickNoteLayout(availableWidth: 139))
        #expect(!MainWindowTitlebarController.usesCompactQuickNoteLayout(availableWidth: 180))
    }

    @Test("quick note accessory visibility follows dashboard context")
    func quickNoteVisibilityMatchesDashboardContext() {
        #expect(MainWindowTitlebarController.showsQuickNoteAccessory(isSearchActive: false, selectedTab: .meetings))
        #expect(!MainWindowTitlebarController.showsQuickNoteAccessory(isSearchActive: true, selectedTab: .meetings))
        #expect(!MainWindowTitlebarController.showsQuickNoteAccessory(isSearchActive: false, selectedTab: .settings))
    }
}
