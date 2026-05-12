import SwiftUI

struct MeetingTranscriptChatView: View {
    let turns: [MeetingTranscriptDisplayTurn]
    let placeholder: String?
    var autoScrollToLatest = false

    private let bottomAnchorID = "meeting-transcript-bottom-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if turns.isEmpty, let placeholder {
                    Text(placeholder)
                        .font(.system(size: 12))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(MuesliTheme.spacing16)
                } else {
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                        ForEach(turns) { turn in
                            VStack(
                                alignment: turn.style == .localSpeaker ? .trailing : .leading,
                                spacing: 4
                            ) {
                                if let timestampLabel = turn.timestampLabel {
                                    Text(timestampLabel)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(MuesliTheme.textTertiary)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(turn.speakerLabel)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(
                                            turn.style == .localSpeaker
                                                ? MuesliTheme.backgroundBase
                                                : MuesliTheme.textSecondary
                                        )
                                    Text(turn.text)
                                        .font(.system(size: 12))
                                        .foregroundStyle(
                                            turn.style == .localSpeaker
                                                ? MuesliTheme.backgroundBase
                                                : MuesliTheme.textPrimary
                                        )
                                        .textSelection(.enabled)
                                }
                                .padding(.horizontal, MuesliTheme.spacing12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                        .fill(
                                            turn.style == .localSpeaker
                                                ? MuesliTheme.accent
                                                : MuesliTheme.surfacePrimary
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                        .strokeBorder(
                                            turn.style == .localSpeaker
                                                ? MuesliTheme.accent.opacity(0.35)
                                                : MuesliTheme.surfaceBorder,
                                            lineWidth: 1
                                        )
                                )
                                .frame(
                                    maxWidth: 420,
                                    alignment: turn.style == .localSpeaker ? .trailing : .leading
                                )
                            }
                            .frame(
                                maxWidth: .infinity,
                                alignment: turn.style == .localSpeaker ? .trailing : .leading
                            )
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorID)
                    }
                    .padding(MuesliTheme.spacing16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .onAppear {
                scrollToBottom(with: proxy, animated: false)
            }
            .onChange(of: turns) { _, _ in
                scrollToBottom(with: proxy, animated: true)
            }
        }
        .background(MuesliTheme.backgroundRaised)
    }

    private func scrollToBottom(with proxy: ScrollViewProxy, animated: Bool) {
        guard autoScrollToLatest else { return }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
    }
}
