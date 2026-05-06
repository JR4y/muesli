import SwiftUI

struct MeetingTranscriptChatView: View {
    let turns: [MeetingTranscriptDisplayTurn]
    let placeholder: String?

    var body: some View {
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
                }
                .padding(MuesliTheme.spacing16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(MuesliTheme.backgroundRaised)
    }
}
