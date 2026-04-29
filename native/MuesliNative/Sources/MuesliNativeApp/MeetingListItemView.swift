import SwiftUI
import MuesliCore

struct MeetingListItemView: View {
    let record: MeetingRecord
    let config: AppConfig
    let isSelected: Bool
    let folders: [MeetingFolder]
    let onSelect: () -> Void
    let onMove: (Int64?) -> Void
    let onCreateFolderAndMove: ((String) -> Void)?
    let onDelete: (() -> Void)?
    @State private var isHovering = false
    @State private var showDeleteConfirmation = false
    @State private var showFolderPopover = false
    @State private var showNewFolderPrompt = false
    @State private var newFolderName = ""

    private var currentFolder: MeetingFolder? {
        guard let fid = record.folderID else { return nil }
        return folders.first(where: { $0.id == fid })
    }

    private var currentFolderName: String? {
        currentFolder?.name
    }

    private var folderButtonLabel: String {
        currentFolderName ?? L10n.text(.meetingUnfiled, config: config)
    }

    private var folderIconName: String {
        currentFolder != nil ? MeetingFolderIcons.resolvedIconName(for: currentFolder) : "folder.badge.plus"
    }

    private var folderIconColor: Color {
        currentFolder.map {
            MeetingFolderColors.color(for: $0, fallback: MuesliTheme.accent.opacity(0.8))
        } ?? MuesliTheme.textTertiary
    }

    private var hasAssociatedEvent: Bool {
        record.calendarEventSnapshot != nil || !(record.calendarEventID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(alignment: .top) {
                Text(record.title)
                    .font(MuesliTheme.headline())
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .lineLimit(2)

                Spacer(minLength: 4)

                if onDelete != nil {
                    deleteButton
                }
            }

            HStack(spacing: MuesliTheme.spacing4) {
                if record.status != .completed {
                    statusBadge
                    Text("\u{2022}")
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                Text(formatMeta())
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)

                if hasAssociatedEvent {
                    Text("\u{2022}")
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .help(L10n.text(.meetingCalendarLinked, config: config))
                }

                if !folders.isEmpty {
                    Text("\u{2022}")
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                    folderMenuButton
                }
            }

            Text(previewText())
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)
                .lineLimit(2)
        }
        .padding(MuesliTheme.spacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .alert(L10n.text(.meetingDeleteTitle, config: config), isPresented: $showDeleteConfirmation) {
            Button(L10n.text(.sidebarDelete, config: config), role: .destructive) { onDelete?() }
            Button(L10n.text(.sidebarCancel, config: config), role: .cancel) {}
        } message: {
            Text(L10n.text(.meetingDeleteMessage, config: config))
        }
    }

    // MARK: - Folder menu button

    @ViewBuilder
    private var folderMenuButton: some View {
        Button {
            showFolderPopover.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: folderIconName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(folderIconColor)
                Text(folderButtonLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(L10n.text(.meetingMoveToFolder, config: config))
        .popover(isPresented: $showFolderPopover, arrowEdge: .leading) {
            VStack(alignment: .leading, spacing: 0) {
                folderPopoverRow(icon: "tray", label: L10n.text(.meetingUnfiled, config: config), isActive: record.folderID == nil) {
                    onMove(nil)
                    showFolderPopover = false
                }
                Divider().padding(.vertical, 4)
                ForEach(folders) { folder in
                    folderPopoverRow(
                        icon: "folder",
                        label: folder.name,
                        color: MeetingFolderColors.color(for: folder, fallback: MuesliTheme.textSecondary),
                        isActive: record.folderID == folder.id
                    ) {
                        onMove(folder.id)
                        showFolderPopover = false
                    }
                }
                if onCreateFolderAndMove != nil {
                    Divider().padding(.vertical, 4)
                    folderPopoverRow(icon: "folder.badge.plus", label: L10n.text(.meetingNewFolderEllipsis, config: config)) {
                        showFolderPopover = false
                        newFolderName = ""
                        showNewFolderPrompt = true
                    }
                }
            }
            .padding(8)
        }
        .alert(L10n.text(.meetingNewFolderTitle, config: config), isPresented: $showNewFolderPrompt) {
            TextField(L10n.text(.sidebarFolderName, config: config), text: $newFolderName)
            Button(L10n.text(.meetingCreate, config: config)) {
                let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    onCreateFolderAndMove?(trimmed)
                }
            }
            Button(L10n.text(.sidebarCancel, config: config), role: .cancel) {}
        } message: {
            Text(L10n.text(.meetingNewFolderMessage, config: config))
        }
    }

    @ViewBuilder
    private func folderPopoverRow(
        icon: String,
        label: String,
        color: Color = MuesliTheme.textSecondary,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(color)
                    .frame(width: 16)
                Text(label)
                    .font(MuesliTheme.callout())
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MuesliTheme.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var deleteButton: some View {
        Button {
            showDeleteConfirmation = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 11))
                .foregroundStyle(
                    isHovering
                        ? MuesliTheme.recording.opacity(0.85)
                        : MuesliTheme.textTertiary
                )
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isHovering ? 1 : 0)
        .help(L10n.text(.meetingDeleteHelp, config: config))
    }

    // MARK: - Formatting

    private var statusBadge: some View {
        Text(record.status.displayLabel)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(record.status.displayColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(record.status.displayColor.opacity(0.12))
            .clipShape(Capsule())
    }

    private func formatMeta() -> String {
        let time = formatTime(record.startTime)
        let duration = formatDuration(record.durationSeconds)
        return "\(time)  \u{2022}  \(duration)"
    }

    private func formatTime(_ raw: String) -> String {
        MeetingDateFormatting.formatCompactMeetingTimestamp(raw)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        if rounded >= 3600 {
            return "\(rounded / 3600)h \((rounded % 3600) / 60)m"
        }
        if rounded >= 60 {
            let m = rounded / 60
            let s = rounded % 60
            return s == 0 ? "\(m)m" : "\(m)m \(s)s"
        }
        return "\(rounded)s"
    }

    private func previewText() -> String {
        let source: String
        if !record.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           record.status != .completed {
            source = record.manualNotes
        } else {
            source = record.formattedNotes.isEmpty ? record.rawTranscript : record.formattedNotes
        }
        let compact = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if compact.count > 88 {
            return String(compact.prefix(85)) + "..."
        }
        return compact.isEmpty ? "No notes yet" : compact
    }

}
