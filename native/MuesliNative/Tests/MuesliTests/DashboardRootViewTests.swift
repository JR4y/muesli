import Testing
@testable import MuesliNativeApp

@Suite("Dashboard root view")
struct DashboardRootViewTests {
    @Test("quick note titlebar control only appears in meetings when search is inactive")
    func quickNoteTitlebarControlVisibility() {
        #expect(DashboardRootView.showsQuickNoteTitlebarControl(isSearchActive: false, selectedTab: .meetings))
        #expect(!DashboardRootView.showsQuickNoteTitlebarControl(isSearchActive: true, selectedTab: .meetings))
        #expect(!DashboardRootView.showsQuickNoteTitlebarControl(isSearchActive: false, selectedTab: .dictations))
        #expect(!DashboardRootView.showsQuickNoteTitlebarControl(isSearchActive: false, selectedTab: .settings))
    }

    @Test("meetings reserve extra titlebar breathing room for quick note")
    func quickNoteTitlebarInset() {
        #expect(DashboardRootView.titlebarContentInset(isSearchActive: false, selectedTab: .meetings) == 36)
        #expect(DashboardRootView.titlebarContentInset(isSearchActive: true, selectedTab: .meetings) == 0)
        #expect(DashboardRootView.titlebarContentInset(isSearchActive: false, selectedTab: .dictations) == 0)
    }

    @Test("sidebar shell starts visible by default")
    @MainActor
    func sidebarStartsVisible() {
        let appState = AppState()

        #expect(appState.isSidebarVisible)
    }
}
