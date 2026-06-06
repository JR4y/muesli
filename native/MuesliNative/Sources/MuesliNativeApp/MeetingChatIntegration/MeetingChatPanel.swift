import SwiftUI
import MuesliCore
import MuesliMeetingChat

struct MeetingChatPanel: View {
    let scope: MeetingChatScope
    let meetings: [MeetingRecord]
    let folders: [MeetingFolder]
    let config: AppConfig
    let isChatGPTAuthenticated: Bool
    let chatStore: (any MeetingChatStoring)?
    let placeholder: String
    let onOpenMeeting: (Int64) -> Void

    @State private var draft = ""
    @State private var messages: [MeetingChatMessage] = []
    @State private var thread: MeetingChatThread?
    @State private var isSending = false
    @State private var includeTranscript = false
    @State private var isExpanded = false
    @State private var isConfirmingClear = false
    @FocusState private var isDraftFocused: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            inputBar
                .zIndex(3)

            if MeetingChatPanelPresentationPolicy.showsConversation(
                isExpanded: isExpanded,
                hasMessages: !messages.isEmpty
            ) {
                floatingConversation
                    .offset(y: -56)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }

            if !mentionSuggestions.isEmpty {
                mentionSuggestionsView
                    .offset(y: -56)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .bottomLeading)
        .task(id: scopeKey) {
            loadThread()
        }
        .onChange(of: isDraftFocused) { _, focused in
            if focused { isExpanded = true }
        }
        .alert(
            L10n.text(.meetingChatClear, config: config),
            isPresented: $isConfirmingClear
        ) {
            Button(L10n.text(.sidebarCancel, config: config), role: .cancel) {}
            Button(L10n.text(.meetingChatClear, config: config), role: .destructive) {
                clearChat()
            }
        } message: {
            Text(L10n.text(.meetingChatClearSyncedMessage, config: config))
        }
        .animation(.snappy(duration: 0.18), value: isExpanded)
        .animation(.snappy(duration: 0.16), value: mentionSuggestions)
    }

    private var inputBar: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MuesliTheme.accent)
                .frame(width: 18)

            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textPrimary)
                .focused($isDraftFocused)
                .disabled(isSending)
                .onSubmit(send)

            contextMenu

            Button(action: send) {
                Image(systemName: isSending ? "hourglass" : "arrow.up.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(canSend ? MuesliTheme.accent : MuesliTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help(L10n.text(.meetingChatSend, config: config))
        }
        .padding(.horizontal, MuesliTheme.spacing12)
        .padding(.vertical, 10)
        .background(MuesliTheme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(isDraftFocused ? MuesliTheme.accent.opacity(0.65) : MuesliTheme.surfaceBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 8)
    }

    private var contextMenu: some View {
        Menu {
            Button {
                includeTranscript.toggle()
            } label: {
                Label(
                    L10n.text(.meetingChatIncludeTranscript, config: config),
                    systemImage: includeTranscript ? "checkmark.circle.fill" : "circle"
                )
            }
            .disabled(!canIncludeTranscript)

            if !canIncludeTranscript, case .folder = scope {
                Text(L10n.text(.meetingChatTranscriptNeedsMention, config: config))
            }

            if !mentionMatches.isEmpty {
                Divider()
                ForEach(mentionMatches, id: \.meetingID) { source in
                    Button {
                        onOpenMeeting(source.meetingID)
                    } label: {
                        Label(source.title, systemImage: "doc.text")
                    }
                }
            }

            if !messages.isEmpty {
                Divider()
                Button(role: .destructive) {
                    isConfirmingClear = true
                } label: {
                    Label(L10n.text(.meetingChatClear, config: config), systemImage: "trash")
                }
                .disabled(isSending)
            }
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(MuesliTheme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .help(L10n.text(.meetingChatMoreContext, config: config))
    }

    private var floatingConversation: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(spacing: MuesliTheme.spacing8) {
                if includeTranscript {
                    contextChip(L10n.text(.meetingChatIncludeTranscript, config: config), icon: "text.alignleft")
                }
                ForEach(mentionMatches, id: \.meetingID) { source in
                    contextChip("@\(source.title)", icon: "at")
                }
                Spacer()
                Button {
                    isExpanded.toggle()
                    if !isExpanded { isDraftFocused = false }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            if messages.isEmpty {
                Text(placeholder)
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                        ForEach(messages) { message in
                            messageBubble(message)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 360)
            }
        }
        .padding(MuesliTheme.spacing12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MuesliTheme.backgroundRaised.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.13), radius: 26, x: 0, y: 18)
    }

    private var mentionSuggestionsView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.text(.meetingChatMentionMeeting, config: config))
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)
                .padding(.horizontal, MuesliTheme.spacing8)
                .padding(.top, 6)
            ForEach(mentionSuggestions, id: \.meetingID) { source in
                Button {
                    draft = MeetingChatMentionResolver.replacingActiveToken(in: draft, with: source)
                    isExpanded = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MuesliTheme.accent)
                        Text(source.title)
                            .font(MuesliTheme.body())
                            .foregroundStyle(MuesliTheme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, MuesliTheme.spacing8)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MuesliTheme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 12)
    }

    private var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canIncludeTranscript: Bool {
        switch scope {
        case .meeting:
            return true
        case .folder:
            return !mentionMatches.isEmpty
        }
    }

    private var mentionableMeetings: [MeetingRecord] {
        switch scope {
        case .meeting:
            return meetings
        case let .folder(id):
            let allowedFolderIDs = descendantFolderIDs(rootID: id).union([id])
            return meetings.filter { meeting in
                meeting.mergedIntoMeetingID == nil
                    && meeting.folderID.map { allowedFolderIDs.contains($0) } == true
            }
        }
    }

    private var mentionMatches: [MeetingChatSource] {
        MeetingChatMentionResolver.matches(in: draft, meetings: mentionableMeetings)
    }

    private var mentionSuggestions: [MeetingChatSource] {
        MeetingChatMentionResolver.suggestions(for: draft, meetings: mentionableMeetings)
            .filter { suggestion in !mentionMatches.contains(where: { $0.meetingID == suggestion.meetingID }) }
    }

    private var scopeKey: String {
        switch scope {
        case let .meeting(id):
            return "meeting:\(id)"
        case let .folder(id):
            return "folder:\(id)"
        }
    }

    private var threadTitle: String {
        switch scope {
        case let .meeting(id):
            return meetings.first(where: { $0.id == id })?.title ?? "Meeting \(id)"
        case let .folder(id):
            return folders.first(where: { $0.id == id })?.name ?? "Folder \(id)"
        }
    }

    private func contextChip(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(MuesliTheme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(MuesliTheme.backgroundBase)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func messageBubble(_ message: MeetingChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.text)
                .font(MuesliTheme.body())
                .foregroundStyle(message.role == .error ? MuesliTheme.recording : MuesliTheme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if message.role == .assistant, !message.sources.isEmpty {
                sourceChips(message.sources)
            }
        }
        .padding(.horizontal, MuesliTheme.spacing12)
        .padding(.vertical, 9)
        .background(message.role == .user ? MuesliTheme.accent.opacity(0.10) : MuesliTheme.surfacePrimary.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sourceChips(_ sources: [MeetingChatSource]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sources, id: \.meetingID) { source in
                    Button {
                        onOpenMeeting(source.meetingID)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 10, weight: .medium))
                            Text(source.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(MuesliTheme.backgroundBase)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending else { return }
        do {
            try ensureThreadLoaded()
        } catch {
            messages.append(MeetingChatMessage(role: .error, text: error.localizedDescription))
            return
        }

        let options = contextOptions(question: question)
        draft = ""
        let context = MeetingChatContextBuilder.build(
            scope: scope,
            question: question,
            meetings: meetings,
            folders: folders,
            options: options
        )
        guard !context.isEmpty else {
            appendPersisted(MeetingChatMessage(role: .user, text: question))
            appendPersisted(MeetingChatMessage(role: .error, text: MeetingChatError.noContext.localizedDescription))
            return
        }

        let memory = MeetingChatMemoryPolicy.memory(
            messages: messages,
            summary: thread?.summary,
            recentLimit: MeetingChatMemoryPolicy.defaultRecentLimit
        )
        appendPersisted(MeetingChatMessage(role: .user, text: question))
        isExpanded = true
        isSending = true

        Task {
            let router = MeetingChatNativeProviderFactory.router(
                config: config,
                isChatGPTAuthenticated: isChatGPTAuthenticated
            )
            do {
                let response = try await router.send(
                    MeetingChatRequest(
                        question: question,
                        context: context,
                        priorMessages: memory.recentMessages,
                        memorySummary: memory.summary
                    )
                )
                await MainActor.run {
                    appendPersisted(
                        MeetingChatMessage(role: .assistant, text: response.text, sources: response.sources)
                    )
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    appendPersisted(MeetingChatMessage(role: .error, text: error.localizedDescription))
                    isSending = false
                }
            }
        }
    }

    private func contextOptions(question: String) -> MeetingChatContextOptions {
        let referencedIDs = Set(
            MeetingChatMentionResolver.matches(in: question, meetings: mentionableMeetings).map(\.meetingID)
        )
        let transcriptIDs: Set<Int64>
        if includeTranscript {
            switch scope {
            case let .meeting(id):
                transcriptIDs = [id]
            case .folder:
                transcriptIDs = referencedIDs
            }
        } else {
            transcriptIDs = []
        }
        return MeetingChatContextOptions(
            referencedMeetingIDs: referencedIDs,
            includeTranscriptMeetingIDs: transcriptIDs
        )
    }

    private func loadThread() {
        guard let chatStore else { return }
        do {
            let snapshot = try chatStore.loadThread(scope: scope, title: threadTitle)
            thread = snapshot.thread
            messages = snapshot.messages
            isExpanded = !snapshot.messages.isEmpty
        } catch {
            thread = nil
            messages = [MeetingChatMessage(role: .error, text: error.localizedDescription)]
            isExpanded = true
        }
    }

    private func ensureThreadLoaded() throws {
        guard thread == nil, let chatStore else { return }
        let snapshot = try chatStore.loadThread(scope: scope, title: threadTitle)
        thread = snapshot.thread
        messages = snapshot.messages
    }

    private func appendPersisted(_ message: MeetingChatMessage) {
        messages.append(message)
        guard let chatStore, let thread else { return }
        do {
            try chatStore.appendMessage(message, to: thread)
        } catch {
            messages.append(MeetingChatMessage(role: .error, text: error.localizedDescription))
        }
    }

    private func clearChat() {
        guard !isSending else { return }
        guard let chatStore else {
            messages = []
            thread = nil
            return
        }
        do {
            try chatStore.clearThread(scope: scope)
            let snapshot = try chatStore.loadThread(scope: scope, title: threadTitle)
            thread = snapshot.thread
            messages = []
        } catch {
            messages.append(MeetingChatMessage(role: .error, text: error.localizedDescription))
            isExpanded = true
        }
    }

    private func descendantFolderIDs(rootID: Int64) -> Set<Int64> {
        var descendants = Set<Int64>()
        var pending = [rootID]
        while let current = pending.popLast() {
            for folder in folders where folder.parentFolderID == current && descendants.insert(folder.id).inserted {
                pending.append(folder.id)
            }
        }
        return descendants
    }
}
