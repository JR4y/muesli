import Testing
@testable import MuesliNativeApp

@Suite("Dashboard root view")
struct DashboardRootViewTests {
    @Test("meetings no longer reserve titlebar breathing room for quick note")
    func quickNoteTitlebarInset() {
        #expect(DashboardRootView.titlebarContentInset(isSearchActive: false, selectedTab: .meetings) == 0)
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
