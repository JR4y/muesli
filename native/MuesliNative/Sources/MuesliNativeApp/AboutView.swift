import SwiftUI
import MuesliCore

struct AboutView: View {
    let appState: AppState

    private let githubURL = "https://github.com/Muesli-HQ/muesli"
    private let donateURL = "https://buymeacoffee.com/phequals7"

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
        return "v\(v)"
    }

    private var appDataPath: String {
        AppIdentity.supportDirectoryURL.path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing32) {
                Text(L10n.text(.aboutTitle, config: appState.config))
                    .font(MuesliTheme.title1())
                    .foregroundStyle(MuesliTheme.textPrimary)

                if let banner = updateBanner {
                    updateBannerView(banner)
                }

                // MARK: - App Info
                sectionHeader(L10n.text(.aboutAppInfoSection, config: appState.config))
                aboutCard {
                    aboutRow(L10n.text(.aboutVersion, config: appState.config)) {
                        Text(version)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(MuesliTheme.textPrimary)
                    }

                    Divider().background(MuesliTheme.surfaceBorder)

                    aboutRow(L10n.text(.aboutCheckForUpdates, config: appState.config)) {
                        Text(updateRowGuidance)
                            .font(MuesliTheme.callout())
                            .foregroundStyle(MuesliTheme.textSecondary)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // MARK: - Support
                sectionHeader(L10n.text(.aboutSupportSection, config: appState.config))
                aboutCard {
                    aboutRow(L10n.text(.aboutSupportDevelopment, config: appState.config)) {
                        Button {
                            if let url = URL(string: donateURL) { NSWorkspace.shared.open(url) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 12))
                                Text(L10n.text(.aboutDonate, config: appState.config))
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, MuesliTheme.spacing20)
                            .padding(.vertical, MuesliTheme.spacing8)
                            .background(MuesliTheme.success)
                            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                        }
                        .buttonStyle(.plain)
                    }

                    Divider().background(MuesliTheme.surfaceBorder)

                    aboutRow(L10n.text(.aboutSourceCode, config: appState.config)) {
                        actionButton(L10n.text(.aboutViewOnGitHub, config: appState.config), icon: "arrow.up.right.square") {
                            if let url = URL(string: githubURL) { NSWorkspace.shared.open(url) }
                        }
                    }
                }

                // MARK: - Data
                sectionHeader(L10n.text(.aboutDataSection, config: appState.config))
                aboutCard {
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                        Text(L10n.text(.aboutAppDataDirectory, config: appState.config))
                            .font(MuesliTheme.body())
                            .foregroundStyle(MuesliTheme.textPrimary)

                        HStack {
                            Text(appDataPath)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(MuesliTheme.textTertiary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            actionButton(L10n.text(.aboutOpen, config: appState.config), icon: "folder") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appDataPath)
                            }
                        }
                    }
                }

                // MARK: - Acknowledgements
                sectionHeader(L10n.text(.aboutAcknowledgementsSection, config: appState.config))
                aboutCard {
                    acknowledgement(
                        name: "FluidAudio by FluidInference",
                        description: "CoreML speech stack powering Parakeet, Qwen3 ASR, Silero VAD, and speaker diarization on Apple Silicon."
                    )
                    Divider().background(MuesliTheme.surfaceBorder)
                    acknowledgement(
                        name: "LocalVQE by localai-org",
                        description: "On-device acoustic echo cancellation powering cleaner meeting transcription."
                    )
                    Divider().background(MuesliTheme.surfaceBorder)
                    acknowledgement(
                        name: "WhisperKit by Argmax",
                        description: "Swift Whisper inference on CoreML/ANE powering the app's Whisper Small, Medium, and Large Turbo backends."
                    )
                }

                Spacer(minLength: MuesliTheme.spacing32)
            }
            .padding(MuesliTheme.spacing32)
        }
        .background(MuesliTheme.backgroundBase)
    }

    // MARK: - Components

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MuesliTheme.textTertiary)
            .textCase(.uppercase)
            .padding(.leading, 2)
    }

    @ViewBuilder
    private func aboutCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(MuesliTheme.spacing20)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private struct UpdateBanner {
        let icon: String
        let title: String
        let message: String
        let tint: Color
    }

    private var updateRowGuidance: String {
        switch appState.sparkleUpdateStatus {
        case .available:
            return "Use the menu bar icon > Check for Updates..."
        case .downloaded:
            return "Use the menu bar updater to finish installation."
        case .checking, .busy, .installing:
            return "Checking..."
        case .failed:
            return "Use the menu bar icon > Check for Updates..."
        case .idle, .upToDate, .disabled:
            return "Use the menu bar icon > Check for Updates..."
        }
    }

    private var updateBanner: UpdateBanner? {
        switch appState.sparkleUpdateStatus {
        case .idle:
            return nil
        case .checking:
            return UpdateBanner(
                icon: "arrow.triangle.2.circlepath",
                title: L10n.text(.aboutCheckingForUpdatesTitle, config: appState.config),
                message: L10n.text(.aboutCheckingForUpdatesMessage, config: appState.config),
                tint: MuesliTheme.transcribing
            )
        case .busy(let message):
            return UpdateBanner(
                icon: "clock.arrow.circlepath",
                title: L10n.text(.aboutUpdaterBusyTitle, config: appState.config),
                message: message,
                tint: MuesliTheme.transcribing
            )
        case .available(let version):
            return UpdateBanner(
                icon: "exclamationmark.triangle.fill",
                title: L10n.text(.aboutUpdateAvailableTitle(version: version), config: appState.config),
                message: L10n.text(.aboutUpdateAvailableMessage, config: appState.config),
                tint: MuesliTheme.transcribing
            )
        case .downloaded(let version):
            return UpdateBanner(
                icon: "exclamationmark.triangle.fill",
                title: L10n.text(.aboutUpdateReadyTitle(version: version), config: appState.config),
                message: L10n.text(.aboutUpdateReadyMessage, config: appState.config),
                tint: MuesliTheme.transcribing
            )
        case .installing(let version):
            return UpdateBanner(
                icon: "arrow.down.circle.fill",
                title: L10n.text(.aboutInstallingUpdateTitle(version: version), config: appState.config),
                message: L10n.text(.aboutInstallingUpdateMessage, config: appState.config),
                tint: MuesliTheme.transcribing
            )
        case .upToDate:
            return UpdateBanner(
                icon: "checkmark.circle.fill",
                title: L10n.text(.aboutUpToDateTitle, config: appState.config),
                message: L10n.text(.aboutUpToDateMessage, config: appState.config),
                tint: MuesliTheme.success
            )
        case .disabled(let message):
            return UpdateBanner(
                icon: "minus.circle.fill",
                title: L10n.text(.aboutUpdatesDisabledTitle, config: appState.config),
                message: message,
                tint: MuesliTheme.textTertiary
            )
        case .failed(let message):
            return UpdateBanner(
                icon: "xmark.octagon.fill",
                title: L10n.text(.aboutUpdateCheckFailedTitle, config: appState.config),
                message: message,
                tint: MuesliTheme.recording
            )
        }
    }

    @ViewBuilder
    private func updateBannerView(_ banner: UpdateBanner) -> some View {
        HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
            Image(systemName: banner.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(banner.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                Text(banner.title)
                    .font(MuesliTheme.headline())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(banner.message)
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: MuesliTheme.spacing16)
        }
        .padding(MuesliTheme.spacing16)
        .background(banner.tint.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(banner.tint.opacity(0.45), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func aboutRow(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textPrimary)
            Spacer()
            control()
        }
        .padding(.vertical, MuesliTheme.spacing8)
    }

    @ViewBuilder
    private func acknowledgement(name: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
            Text(name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MuesliTheme.textPrimary)
            Text(description)
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, MuesliTheme.spacing8)
    }

    @ViewBuilder
    private func actionButton(_ title: String, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(MuesliTheme.textPrimary)
            .padding(.horizontal, MuesliTheme.spacing16)
            .padding(.vertical, MuesliTheme.spacing8)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
