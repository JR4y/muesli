import SwiftUI
import MuesliCore

struct SidebarView: View {
    private let sidebarIconColumnWidth: CGFloat = 20
    private let meetingsTrailingColumnWidth: CGFloat = 24
    private let sidebarRowHorizontalPadding: CGFloat = 16
    private let sidebarRowOuterPadding: CGFloat = 8

    let appState: AppState
    let controller: MuesliController
    @Environment(\.colorScheme) private var colorScheme
    @State private var meetingsExpanded = true
    @State private var renamingFolderID: Int64?
    @State private var renamingFolderName = ""
    @State private var folderToDelete: MeetingFolder?
    @State private var showDeleteConfirmation = false
    @State private var expandedFolderIDs = Set<Int64>()
    @State private var hasInitializedFolderExpansion = false
    @FocusState private var isSearchFieldFocused: Bool

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { appState.searchQuery },
            set: { controller.performSearch(query: $0) }
        )
    }

    private var userName: String {
        appState.config.userName
    }

    private struct UpdateCTA {
        let label: String
        let icon: String
        let foreground: Color
        let accessibilityLabel: String
        let tooltip: String
    }

    private var pendingUpdateCTA: UpdateCTA? {
        switch appState.sparkleUpdateStatus {
        case .available:
            return UpdateCTA(
                label: "Update",
                icon: "arrow.down",
                foreground: updateCTAForeground,
                accessibilityLabel: L10n.text(.sidebarUpdateAvailable, config: appState.config),
                tooltip: "Open About for update instructions"
            )
        case .downloaded:
            return UpdateCTA(
                label: "Update",
                icon: "arrow.clockwise",
                foreground: updateCTAForeground,
                accessibilityLabel: L10n.text(.sidebarUpdateReady, config: appState.config),
                tooltip: "Open About for update instructions"
            )
        case .idle, .checking, .busy, .installing, .upToDate, .disabled, .failed:
            return nil
        }
    }

    private var updateCTAForeground: Color {
        let accentHex = appState.config.recordingColorHex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .lowercased()

        let defaultAccentHex = colorScheme == .dark
            ? MuesliTheme.defaultAccentDarkHex
            : MuesliTheme.defaultAccentLightHex

        let value: UInt64
        if accentHex == "1e1e2e" {
            value = UInt64(defaultAccentHex)
        } else {
            guard accentHex.count == 6,
                  let parsedValue = UInt64(accentHex, radix: 16) else {
                value = UInt64(defaultAccentHex)
                return foregroundColor(forAccentHex: value)
            }
            value = parsedValue
        }

        return foregroundColor(forAccentHex: value)
    }

    private func foregroundColor(forAccentHex value: UInt64) -> Color {
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        // 0.45 on raw sRGB approximates the WCAG 0.18 threshold on linearized luminance.
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.45 ? Color.black.opacity(0.88) : Color.white
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
            sidebarHeader
            searchBar

            meetingsSection
            sidebarItem(tab: .dictations, icon: "mic.fill", label: L10n.text(.sidebarDictations, config: appState.config))

            Spacer()

            modelPreparationStatus
            sidebarItem(tab: .settings, icon: "gearshape", label: L10n.text(.sidebarSettings, config: appState.config))
            sidebarItem(tab: .about, icon: "info.circle", label: L10n.text(.sidebarAbout, config: appState.config), updateCTA: pendingUpdateCTA)
            darkModeToggle
                .padding(.bottom, MuesliTheme.spacing16)
        }
        .frame(maxHeight: .infinity)
        .background(MuesliTheme.backgroundDeep)
        .onChange(of: appState.selectedTab) { _, tab in
            if tab == .meetings {
                meetingsExpanded = true
            }
        }
        .onChange(of: appState.folders.map(\.id)) { _, ids in
            guard !hasInitializedFolderExpansion else { return }
            expandedFolderIDs = Set(ids)
            hasInitializedFolderExpansion = true
        }
        .alert(
            "\(L10n.text(.sidebarDelete, config: appState.config)) \"\(folderToDelete?.name ?? "")\"?",
            isPresented: $showDeleteConfirmation
        ) {
            Button(L10n.text(.sidebarCancel, config: appState.config), role: .cancel) {
                folderToDelete = nil
            }
            Button(L10n.text(.sidebarDelete, config: appState.config), role: .destructive) {
                if let folder = folderToDelete {
                    controller.deleteFolder(id: folder.id)
                    controller.showMeetingsHome(folderID: appState.selectedFolderID)
                }
                folderToDelete = nil
            }
        } message: {
            let count = folderToDelete.map { folder in
                appState.meetingCountsByFolder[folder.id] ?? 0
            } ?? 0
            if count > 0 {
                Text(L10n.text(.sidebarMeetingsMovedToUnfiled(count: count), config: appState.config))
            } else {
                Text(L10n.text(.sidebarFolderRemoved, config: appState.config))
            }
        }
    }

    @ViewBuilder
    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
            HStack(spacing: MuesliTheme.spacing12) {
                Group {
                    if appState.config.menuBarIcon == "muesli",
                       let img = MenuBarIconRenderer.make(choice: "muesli") {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: appState.config.menuBarIcon)
                    }
                }
                .frame(width: 22, height: 22)
                .foregroundStyle(MuesliTheme.accent)
                Text("muesli")
                    .font(MuesliTheme.title2())
                    .foregroundStyle(MuesliTheme.textPrimary)
            }
            if !userName.isEmpty {
                Text(L10n.text(.sidebarGreeting(name: userName), config: appState.config))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .padding(.leading, 34)
            }
        }
        .padding(.horizontal, MuesliTheme.spacing16)
        .padding(.top, MuesliTheme.spacing24)
        .padding(.bottom, MuesliTheme.spacing20)
    }

    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(MuesliTheme.textTertiary)
            TextField(L10n.text(.sidebarSearchPlaceholder, config: appState.config), text: searchTextBinding)
                .textFieldStyle(.plain)
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textPrimary)
                .focused($isSearchFieldFocused)
            if !appState.searchQuery.isEmpty {
                Button {
                    controller.clearSearch()
                    isSearchFieldFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
        .padding(.horizontal, sidebarRowOuterPadding)
        .padding(.bottom, MuesliTheme.spacing8)
        .onChange(of: appState.focusSearchField) { _, shouldFocus in
            if shouldFocus {
                isSearchFieldFocused = true
                appState.focusSearchField = false
            }
        }
    }

    @ViewBuilder
    private var meetingsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            let isSelected = appState.selectedTab == .meetings
            HStack(spacing: MuesliTheme.spacing12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        meetingsExpanded = true
                    }
                    controller.showMeetingsHome()
                } label: {
                    HStack(spacing: MuesliTheme.spacing12) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isSelected ? MuesliTheme.accent : MuesliTheme.textSecondary)
                            .frame(width: sidebarIconColumnWidth)
                        Text(L10n.text(.sidebarMeetings, config: appState.config))
                            .font(MuesliTheme.headline())
                            .foregroundStyle(isSelected ? MuesliTheme.textPrimary : MuesliTheme.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        meetingsExpanded.toggle()
                    }
                } label: {
                    Image(systemName: meetingsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? MuesliTheme.textSecondary : MuesliTheme.textTertiary)
                        .frame(width: meetingsTrailingColumnWidth, height: 18)
                }
                .buttonStyle(.plain)

                Button(action: { createNewFolder() }) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? MuesliTheme.textSecondary : MuesliTheme.textTertiary)
                        .frame(width: meetingsTrailingColumnWidth, height: 18)
                }
                .buttonStyle(.plain)
                .help(L10n.text(.sidebarNewMeetingFolder, config: appState.config))
            }
            .padding(.horizontal, sidebarRowHorizontalPadding)
            .padding(.vertical, MuesliTheme.spacing8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .fill(isSelected ? MuesliTheme.surfaceSelected : Color.clear)
            )
            .contentShape(Rectangle())
            .padding(.horizontal, sidebarRowOuterPadding)

            if meetingsExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    meetingFilterRow(
                        icon: "tray.2",
                        label: L10n.text(.sidebarAllMeetings, config: appState.config),
                        count: appState.totalMeetingCount,
                        isSelected: appState.selectedTab == .meetings && appState.selectedFolderID == nil
                    ) {
                        controller.showMeetingsHome()
                    }

                    ForEach(rootFolders) { folder in
                        folderTree(folder, depth: 0)
                    }
                }
                .padding(.horizontal, sidebarRowOuterPadding)
            }
        }
    }

    @ViewBuilder
    private var modelPreparationStatus: some View {
        if let title = appState.modelPreparationTitle {
            HStack(spacing: MuesliTheme.spacing8) {
                Group {
                    if appState.modelPreparationIsComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(MuesliTheme.success)
                    } else if appState.isModelPreparingAfterDownload || appState.modelPreparationProgress == nil {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        ProgressView(value: appState.modelPreparationProgress ?? 0, total: 1)
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    }
                }
                .frame(width: sidebarIconColumnWidth, height: sidebarIconColumnWidth)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .lineLimit(1)
                    if let detail = appState.modelPreparationDetail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(MuesliTheme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, sidebarRowHorizontalPadding)
            .padding(.vertical, MuesliTheme.spacing8)
            .background(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .fill(MuesliTheme.backgroundRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
            .padding(.horizontal, sidebarRowOuterPadding)
            .padding(.bottom, MuesliTheme.spacing4)
        }
    }

    @ViewBuilder
    private func sidebarItem(tab: DashboardTab, icon: String, label: String, updateCTA: UpdateCTA? = nil) -> some View {
        let isSelected = appState.selectedTab == tab
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                appState.selectedTab = tab
            }
        } label: {
            HStack(spacing: MuesliTheme.spacing12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? MuesliTheme.accent : MuesliTheme.textSecondary)
                    .frame(width: sidebarIconColumnWidth, height: sidebarIconColumnWidth, alignment: .center)
                    .offset(y: icon == "square.and.arrow.down" ? -1 : 0)
                Text(label)
                    .font(MuesliTheme.headline())
                    .foregroundStyle(isSelected ? MuesliTheme.textPrimary : MuesliTheme.textSecondary)
                Spacer()
                if let updateCTA {
                    HStack(spacing: 4) {
                        Image(systemName: updateCTA.icon)
                            .font(.system(size: 9, weight: .bold))
                        Text(updateCTA.label)
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(updateCTA.foreground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(MuesliTheme.accent)
                    .clipShape(Capsule())
                    .shadow(color: MuesliTheme.accent.opacity(0.35), radius: 8, x: 0, y: 2)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(updateCTA.accessibilityLabel)
                    .help(updateCTA.tooltip)
                }
            }
            .padding(.horizontal, sidebarRowHorizontalPadding)
            .padding(.vertical, MuesliTheme.spacing8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .fill(isSelected ? MuesliTheme.surfaceSelected : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, sidebarRowOuterPadding)
    }

    @ViewBuilder
    private var darkModeToggle: some View {
        let isDark = appState.config.darkMode
        HStack(spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    controller.updateConfig { $0.darkMode = false }
                }
            } label: {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(!isDark ? MuesliTheme.accent : MuesliTheme.textTertiary)
                    .frame(width: 28, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(!isDark ? MuesliTheme.surfaceSelected : Color.clear)
                    )
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    controller.updateConfig { $0.darkMode = true }
                }
            } label: {
                Image(systemName: "moon.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isDark ? MuesliTheme.accent : MuesliTheme.textTertiary)
                    .frame(width: 28, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isDark ? MuesliTheme.surfaceSelected : Color.clear)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .fill(MuesliTheme.backgroundRaised)
        )
        .padding(.horizontal, sidebarRowOuterPadding)
        .padding(.leading, sidebarRowHorizontalPadding)
        .padding(.bottom, MuesliTheme.spacing4)
    }

    @ViewBuilder
    private func meetingFilterRow(
        icon: String,
        iconColor: Color? = nil,
        label: String,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(iconColor ?? (isSelected ? MuesliTheme.accent : MuesliTheme.textTertiary))
                .frame(width: sidebarIconColumnWidth)
            Text(label)
                .font(MuesliTheme.callout())
                .foregroundStyle(isSelected ? MuesliTheme.textPrimary : MuesliTheme.textSecondary)
                .lineLimit(1)
            Spacer()
            Text(formattedCount(count))
                .font(MuesliTheme.caption())
                .monospacedDigit()
                .foregroundStyle(MuesliTheme.textTertiary)
                .frame(minWidth: meetingsTrailingColumnWidth, alignment: .center)
        }
        .padding(.horizontal, sidebarRowHorizontalPadding)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .fill(isSelected ? MuesliTheme.surfaceSelected.opacity(0.6) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    private func folderTree(_ folder: MeetingFolder, depth: Int) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 2) {
                if renamingFolderID == folder.id {
                    folderRenameField(folder: folder, depth: depth)
                } else {
                    folderTreeRow(folder: folder, depth: depth)
                        .contextMenu {
                            Button(L10n.text(.sidebarRename, config: appState.config)) {
                                renamingFolderID = folder.id
                                renamingFolderName = folder.name
                            }
                            Button(L10n.text(.sidebarAddSubfolder, config: appState.config)) {
                                createNewFolder(parentFolderID: folder.id)
                            }
                            Divider()
                            Button(L10n.text(.sidebarDelete, config: appState.config), role: .destructive) {
                                folderToDelete = folder
                                showDeleteConfirmation = true
                            }
                        }
                }

                if appState.hasChildFolders(folder.id), isFolderExpanded(folder.id) {
                    ForEach(appState.childFolders(of: folder.id)) { child in
                        folderTree(child, depth: depth + 1)
                    }
                }
            }
        )
    }

    @ViewBuilder
    private func folderTreeRow(folder: MeetingFolder, depth: Int) -> some View {
        let hasChildren = appState.hasChildFolders(folder.id)
        let isSelected = appState.selectedTab == .meetings && appState.selectedFolderID == folder.id

        HStack(spacing: MuesliTheme.spacing8) {
            Color.clear
                .frame(width: CGFloat(depth) * 12, height: 1)

            if hasChildren {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        toggleFolderExpansion(folder.id)
                    }
                } label: {
                    Image(systemName: isFolderExpanded(folder.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: 12, height: 12)
            }

            Image(systemName: MeetingFolderIcons.resolvedIconName(for: folder))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MeetingFolderColors.color(for: folder, fallback: MuesliTheme.accent))
                .frame(width: sidebarIconColumnWidth)

            Text(folder.name)
                .font(MuesliTheme.callout())
                .foregroundStyle(isSelected ? MuesliTheme.textPrimary : MuesliTheme.textSecondary)
                .lineLimit(1)

            Spacer()

            Text(formattedCount(appState.meetingCountsByFolder[folder.id] ?? 0))
                .font(MuesliTheme.caption())
                .monospacedDigit()
                .foregroundStyle(MuesliTheme.textTertiary)
                .frame(minWidth: meetingsTrailingColumnWidth, alignment: .center)
        }
        .padding(.horizontal, sidebarRowHorizontalPadding)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .fill(isSelected ? MuesliTheme.surfaceSelected.opacity(0.6) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            controller.showMeetingsHome(folderID: folder.id)
        }
    }

    @ViewBuilder
    private func folderRenameField(folder: MeetingFolder, depth: Int) -> some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Color.clear
                .frame(width: CGFloat(depth) * 12 + 12, height: 1)
            Image(systemName: MeetingFolderIcons.resolvedIconName(for: folder))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MeetingFolderColors.color(for: folder, fallback: MuesliTheme.accent))
                .frame(width: sidebarIconColumnWidth)
            TextField(L10n.text(.sidebarFolderName, config: appState.config), text: $renamingFolderName)
                .font(MuesliTheme.callout())
                .textFieldStyle(.plain)
                .onSubmit {
                    let trimmed = renamingFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        controller.renameFolder(id: folder.id, name: trimmed)
                    }
                    renamingFolderID = nil
                }
        }
        .padding(.horizontal, sidebarRowHorizontalPadding)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .fill(MuesliTheme.surfaceSelected.opacity(0.6))
        )
    }

    private func formattedCount(_ count: Int) -> String {
        if count < 1000 { return "\(count)" }
        if count < 10000 {
            let k = Double(count) / 1000.0
            return String(format: "%.1fk", Double(Int(k * 10)) / 10.0)
        }
        return "\(count / 1000)k"
    }

    private var rootFolders: [MeetingFolder] {
        appState.childFolders(of: nil)
    }

    private func isFolderExpanded(_ folderID: Int64) -> Bool {
        expandedFolderIDs.contains(folderID)
    }

    private func toggleFolderExpansion(_ folderID: Int64) {
        if isFolderExpanded(folderID) {
            expandedFolderIDs.remove(folderID)
        } else {
            expandedFolderIDs.insert(folderID)
        }
    }

    private func createNewFolder(parentFolderID: Int64? = nil) {
        let newFolderName = L10n.text(.sidebarNewFolder, config: appState.config)
        if let id = controller.createFolder(name: newFolderName, parentFolderID: parentFolderID) {
            withAnimation(.easeInOut(duration: 0.15)) {
                meetingsExpanded = true
            }
            if let parentFolderID {
                expandedFolderIDs.insert(parentFolderID)
            }
            expandedFolderIDs.insert(id)
            renamingFolderID = id
            renamingFolderName = newFolderName
            controller.showMeetingsHome(folderID: id)
        }
    }
}
