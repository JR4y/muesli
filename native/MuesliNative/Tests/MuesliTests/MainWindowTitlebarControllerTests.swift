import CoreGraphics
import Testing
@testable import MuesliNativeApp

@Suite("Main window titlebar controller")
struct MainWindowTitlebarControllerTests {
    @Test("quick note accessory uses the icon-only variant only on narrow windows")
    func compactQuickNoteThreshold() {
        #expect(MainWindowTitlebarController.usesCompactQuickNoteLayout(availableWidth: 759))
        #expect(!MainWindowTitlebarController.usesCompactQuickNoteLayout(availableWidth: 900))
    }

    @Test("quick note accessory visibility follows dashboard context")
    func quickNoteVisibilityMatchesDashboardContext() {
        #expect(MainWindowTitlebarController.showsQuickNoteAccessory(isSearchActive: false, selectedTab: .meetings))
        #expect(!MainWindowTitlebarController.showsQuickNoteAccessory(isSearchActive: true, selectedTab: .meetings))
        #expect(!MainWindowTitlebarController.showsQuickNoteAccessory(isSearchActive: false, selectedTab: .settings))
    }

    @Test("quick note accessory shows a short label in standard windows")
    func quickNoteAccessoryMetrics() {
        let metrics = MainWindowTitlebarController.quickNoteAccessoryMetrics(availableWidth: 1120)

        #expect(metrics.accessorySize.width == 92)
        #expect(metrics.controlHeight == 26)
        #expect(metrics.showsLabel)
    }

    @Test("quick note accessory falls back to icon-only in narrow windows")
    func quickNoteAccessoryMetricsNarrow() {
        let metrics = MainWindowTitlebarController.quickNoteAccessoryMetrics(availableWidth: 720)

        #expect(metrics.accessorySize.width == 52)
        #expect(!metrics.showsLabel)
    }
}
