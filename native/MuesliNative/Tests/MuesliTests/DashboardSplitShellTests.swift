import Testing
import SwiftUI
@testable import MuesliNativeApp

@Suite("Dashboard split shell")
struct DashboardSplitShellTests {
    @Test("sidebar width resolves to zero when hidden")
    func hiddenSidebarUsesZeroWidth() {
        #expect(DashboardSplitShell<EmptyView, EmptyView>.resolvedSidebarWidth(isVisible: false, preferredWidth: 260) == 0)
    }

    @Test("sidebar width is clamped to the supported range when visible")
    func visibleSidebarWidthIsClamped() {
        #expect(DashboardSplitShell<EmptyView, EmptyView>.resolvedSidebarWidth(isVisible: true, preferredWidth: 120) == 240)
        #expect(DashboardSplitShell<EmptyView, EmptyView>.resolvedSidebarWidth(isVisible: true, preferredWidth: 260) == 260)
        #expect(DashboardSplitShell<EmptyView, EmptyView>.resolvedSidebarWidth(isVisible: true, preferredWidth: 420) == 300)
    }
}
