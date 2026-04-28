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
    @State private var draggingFolderID: Int64?
    @State private var dragOrderedFolders: [MeetingFolder]?
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
                label: L10n.text(.sidebarUpdateNow, config: appState.config),
                icon: "arrow.down",
                foreground: updateCTAForeground,
                accessibilityLabel: L10n.text(.sidebarUpdateAvailable, config: appState.config),
                tooltip: L10n.text(.sidebarUpdateTooltip, config: appState.config)
            )
        case .downloaded:
            return UpdateCTA(
                label: L10n.text(.sidebarRestart, config: appState.config),
                icon: "arrow.clockwise",
                foreground: updateCTAForeground,
                accessibilityLabel: L10n.text(.sidebarUpdateReady, config: appState.config),
                tooltip: L10n.text(.sidebarRestartTooltip, config: appState.config)
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
            sidebarItem(tab: .dictionary, icon: "character.book.closed", label: L10n.text(.sidebarDictionary, config: appState.config))
            sidebarItem(tab: .models, icon: "square.and.arrow.down", label: L10n.text(.sidebarModels, config: appState.config))
            sidebarItem(tab: .shortcuts, icon: "keyboard", label: L10n.text(.sidebarShortcuts, config: appState.config))

            Spacer()

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
            // Reset drag state if user navigates away during a drag
            if draggingFolderID != nil {
                draggingFolderID = nil
                dragOrderedFolders = nil
            }
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

                Button(action: createNewFolder) {
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
            .background(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .fill(isSelected ? MuesliTheme.surfaceSelected : Color.clear)
            )
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

                    ForEach(dragOrderedFolders ?? appState.folders) { folder in
                        if renamingFolderID == folder.id {
                            folderRenameField(folder: folder)
                        } else {
                            meetingFilterRow(
                                icon: "folder",
                                iconColor: MeetingFolderColors.color(for: folder, fallback: MuesliTheme.accent),
                                label: folder.name,
                                count: appState.meetingCountsByFolder[folder.id] ?? 0,
                                isSelected: appState.selectedTab == .meetings && appState.selectedFolderID == folder.id
                            ) {
                                controller.showMeetingsHome(folderID: folder.id)
                            }
                            .opacity(draggingFolderID == folder.id ? 0.1 : 1)
                            .onDrag {
                                draggingFolderID = folder.id
                                dragOrderedFolders = appState.folders
                                return NSItemProvider(object: "\(folder.id)" as NSString)
                            }
                            .onDrop(of: [.text], delegate: FolderDropDelegate(
                                folderID: folder.id,
                                dragOrderedFolders: $dragOrderedFolders,
                                draggingFolderID: $draggingFolderID,
                                commitOrder: { ids in controller.reorderFolders(ids: ids) }
                            ))
                            .contextMenu {
                                Button(L10n.text(.sidebarRename, config: appState.config)) {
                                    renamingFolderID = folder.id
                                    renamingFolderName = folder.name
                                }
                                Menu(L10n.text(.sidebarFolderColor, config: appState.config)) {
                                    ForEach(MeetingFolderColors.all) { option in
                                        Button {
                                            controller.updateFolderColor(id: folder.id, colorHex: option.hex)
                                        } label: {
                                            HStack(spacing: 8) {
                                                Circle()
                                                    .fill(option.swatchColor)
                                                    .frame(width: 9, height: 9)
                                                Text(L10n.text(option.labelKey, config: appState.config))
                                            }
                                        }
                                    }
                                }
                                Divider()
                                Button(L10n.text(.sidebarDelete, config: appState.config), role: .destructive) {
                                    folderToDelete = folder
                                    showDeleteConfirmation = true
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, sidebarRowOuterPadding)
            }
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
                    .frame(width: sidebarIconColumnWidth)
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
            .background(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .fill(isSelected ? MuesliTheme.surfaceSelected : Color.clear)
            )
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
        .background(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .fill(isSelected ? MuesliTheme.surfaceSelected.opacity(0.6) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    @ViewBuilder
    private func folderRenameField(folder: MeetingFolder) -> some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Image(systemName: "folder")
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

    private func createNewFolder() {
        let newFolderName = L10n.text(.sidebarNewFolder, config: appState.config)
        if let id = controller.createFolder(name: newFolderName) {
            withAnimation(.easeInOut(duration: 0.15)) {
                meetingsExpanded = true
            }
            renamingFolderID = id
            renamingFolderName = newFolderName
            controller.showMeetingsHome(folderID: id)
        }
    }
}

private struct FolderDropDelegate: DropDelegate {
    let folderID: Int64
    @Binding var dragOrderedFolders: [MeetingFolder]?
    @Binding var draggingFolderID: Int64?
    let commitOrder: ([Int64]) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragID = draggingFolderID, dragID != folderID,
              var folders = dragOrderedFolders else { return }
        guard let fromIndex = folders.firstIndex(where: { $0.id == dragID }),
              let toIndex = folders.firstIndex(where: { $0.id == folderID }) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            folders.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            dragOrderedFolders = folders
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        if let folders = dragOrderedFolders {
            commitOrder(folders.map(\.id))
        }
        draggingFolderID = nil
        dragOrderedFolders = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
