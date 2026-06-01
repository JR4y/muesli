import SwiftUI

struct DashboardSplitShell<Sidebar: View, Detail: View>: View {
    static var minSidebarWidth: CGFloat { 240 }
    static var idealSidebarWidth: CGFloat { 260 }
    static var maxSidebarWidth: CGFloat { 300 }

    @Binding private var isSidebarVisible: Bool
    private let preferredSidebarWidth: CGFloat
    private let sidebar: Sidebar
    private let detail: Detail

    init(
        isSidebarVisible: Binding<Bool>,
        preferredSidebarWidth: CGFloat = Self.idealSidebarWidth,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        _isSidebarVisible = isSidebarVisible
        self.preferredSidebarWidth = preferredSidebarWidth
        self.sidebar = sidebar()
        self.detail = detail()
    }

    static func resolvedSidebarWidth(isVisible: Bool, preferredWidth: CGFloat) -> CGFloat {
        guard isVisible else { return 0 }
        return min(max(preferredWidth, minSidebarWidth), maxSidebarWidth)
    }

    var body: some View {
        HSplitView {
            if isSidebarVisible {
                sidebar
                    .frame(
                        minWidth: Self.minSidebarWidth,
                        idealWidth: Self.resolvedSidebarWidth(
                            isVisible: true,
                            preferredWidth: preferredSidebarWidth
                        ),
                        maxWidth: Self.maxSidebarWidth,
                        maxHeight: .infinity
                    )
            }

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
