import AVFoundation
import SwiftUI
import MuesliCore

struct SettingsView: View {
    private enum PendingDataDestruction {
        case dictations
        case meetings

        func title(config: AppConfig) -> String {
            switch self {
            case .dictations:
                return "\(L10n.text(.settingsClearDictationHistory, config: config))?"
            case .meetings:
                return "\(L10n.text(.settingsClearMeetingHistory, config: config))?"
            }
        }

        func message(config: AppConfig) -> String {
            switch self {
            case .dictations:
                return L10n.text(.dictationsDeleteMessage, config: config)
            case .meetings:
                return L10n.text(.settingsClearMeetingHistoryMessage, config: config)
            }
        }

        func confirmLabel(config: AppConfig) -> String {
            switch self {
            case .dictations:
                return L10n.text(.settingsClearDictationHistory, config: config)
            case .meetings:
                return L10n.text(.settingsClearMeetingHistory, config: config)
            }
        }
    }

    let appState: AppState
    let controller: MuesliController

    @State private var chatGPTSignInError: String?
    @State private var isSigningInChatGPT = false
    @State private var googleCalSignInError: String?
    @State private var isSigningInGoogleCal = false
    @State private var pendingDataDestruction: PendingDataDestruction?
    @State private var isPreviewingClip = false
    @State private var downloadedBackendOptions: [BackendOption] = []
    @State private var downloadedPostProcOptions: [PostProcessorOption] = []
    @State private var permissionPollTimer: Timer?
    @State private var micGranted = false
    @State private var accessibilityGranted = false
    @State private var inputMonitoringGranted = false
    @State private var screenRecordingGranted = false
    @State private var systemAudioGranted = false
    @State private var isCheckingSystemAudioPermission = false
    @State private var openRouterFreeModels: [SummaryModelPreset] = []
    @State private var isLoadingOpenRouterFreeModels = false
    @State private var openRouterFreeModelsError: String?

    // Uniform width for all right-side controls
    private let controlWidth: CGFloat = 220
    private let meetingControlWidth: CGFloat = 275

    private var dictationBackendOptions: [BackendOption] {
        backendOptions(including: appState.selectedBackend)
    }

    private var meetingBackendOptions: [BackendOption] {
        backendOptions(including: appState.selectedMeetingTranscriptionBackend)
    }

    private var selectedCohereLanguage: CohereTranscribeLanguage {
        appState.config.resolvedCohereLanguage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsHeader
            settingsPanePicker
            paneContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(MuesliTheme.backgroundBase)
        .onAppear {
            refreshDownloadedModelOptions()
            startPermissionPolling()
            if appState.selectedMeetingSummaryBackend == .openRouter {
                loadOpenRouterFreeModelsIfNeeded()
            }
        }
        .onDisappear {
            SoundController.stopMaraudersMapClip()
            isPreviewingClip = false
            stopPermissionPolling()
        }
        .onChange(of: appState.selectedTab) { _, tab in
            if tab == .settings {
                refreshDownloadedModelOptions()
                refreshPermissionStatuses()
            }
        }
        .onChange(of: appState.selectedBackend) { _, _ in
            refreshDownloadedModelOptions()
        }
        .onChange(of: appState.selectedMeetingTranscriptionBackend) { _, _ in
            refreshDownloadedModelOptions()
        }
        .onChange(of: appState.selectedMeetingSummaryBackend) { _, backend in
            if backend == .openRouter {
                loadOpenRouterFreeModelsIfNeeded()
            }
        }
        .alert(
            pendingDataDestruction?.title(config: appState.config) ?? L10n.text(.settingsConfirmDestructiveAction, config: appState.config),
            isPresented: Binding(
                get: { pendingDataDestruction != nil },
                set: { if !$0 { pendingDataDestruction = nil } }
            )
        ) {
            Button(L10n.text(.sidebarCancel, config: appState.config), role: .cancel) {
                pendingDataDestruction = nil
            }
            Button(
                pendingDataDestruction?.confirmLabel(config: appState.config) ?? L10n.text(.sidebarDelete, config: appState.config),
                role: .destructive
            ) {
                switch pendingDataDestruction {
                case .dictations:
                    controller.clearDictationHistory()
                case .meetings:
                    controller.clearMeetingHistory()
                case nil:
                    break
                }
                pendingDataDestruction = nil
            }
        } message: {
            Text(pendingDataDestruction?.message(config: appState.config) ?? "")
        }
    }

    private func refreshDownloadedModelOptions() {
        downloadedBackendOptions = BackendOption.downloaded
        downloadedPostProcOptions = PostProcessorOption.downloaded
    }

    private func backendOptions(including selection: BackendOption) -> [BackendOption] {
        var options = downloadedBackendOptions
        if !options.contains(where: { $0 == selection }) {
            options.insert(selection, at: 0)
        }
        return options
    }

    private static let accentPresets: [(hex: String, name: String)] = [
        ("2563eb", "Blue"),
        ("ef4444", "Red"),
        ("f59e0b", "Amber"),
        ("10b981", "Green"),
        ("8b5cf6", "Purple"),
        ("ec4899", "Pink"),
        ("1e1e2e", "Dark"),
    ]

    private var sharedContextDescription: String {
        L10n.text(.settingsSharedContextDescription, config: appState.config)
    }

    private var customIndicatorPositionLabel: String {
        L10n.text(.settingsCustomIndicatorPosition, config: appState.config)
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text(.settingsTitle, config: appState.config))
                .font(MuesliTheme.title1())
                .foregroundStyle(MuesliTheme.textPrimary)
        }
        .padding(.horizontal, MuesliTheme.spacing32)
        .padding(.top, MuesliTheme.spacing32)
        .padding(.bottom, MuesliTheme.spacing20)
    }

    private var settingsPanePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MuesliTheme.spacing8) {
                ForEach(SettingsPane.allCases) { pane in
                    let isSelected = appState.selectedSettingsPane == pane
                    Button {
                        appState.selectedSettingsPane = pane
                    } label: {
                        Text(paneTitle(pane))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isSelected ? MuesliTheme.textPrimary : MuesliTheme.textSecondary)
                            .padding(.horizontal, MuesliTheme.spacing12)
                            .padding(.vertical, MuesliTheme.spacing8)
                            .background(
                                Capsule()
                                    .fill(isSelected ? MuesliTheme.surfaceSelected : MuesliTheme.surfacePrimary.opacity(0.55))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        isSelected ? MuesliTheme.accent.opacity(0.3) : MuesliTheme.surfaceBorder,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, MuesliTheme.spacing32)
            .padding(.bottom, MuesliTheme.spacing20)
        }
    }

    private func paneTitle(_ pane: SettingsPane) -> String {
        switch pane {
        case .general:
            return L10n.text(.settingsPaneGeneral, config: appState.config)
        case .dictation:
            return L10n.text(.settingsPaneDictation, config: appState.config)
        case .meetings:
            return L10n.text(.settingsPaneMeetings, config: appState.config)
        case .appearance:
            return L10n.text(.settingsPaneAppearance, config: appState.config)
        case .dictionary:
            return L10n.text(.dictionaryTitle, config: appState.config)
        case .models:
            return L10n.text(.sidebarModels, config: appState.config)
        case .shortcuts:
            return L10n.text(.shortcutsTitle, config: appState.config)
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        switch appState.selectedSettingsPane {
        case .general:
            settingsScrollPane { generalSettingsPane }
        case .dictation:
            settingsScrollPane { dictationSettingsPane }
        case .meetings:
            settingsScrollPane { meetingsSettingsPane }
        case .appearance:
            settingsScrollPane { appearanceSettingsPane }
        case .dictionary:
            DictionaryView(appState: appState, controller: controller)
        case .models:
            ModelsView(appState: appState, controller: controller)
        case .shortcuts:
            ShortcutsView(appState: appState, controller: controller)
        }
    }

    private func settingsScrollPane<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
                content()
            }
            .padding(.horizontal, MuesliTheme.spacing32)
            .padding(.bottom, MuesliTheme.spacing32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var generalSettingsPane: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
            settingsSection(L10n.text(.settingsGeneralSection, config: appState.config)) {
                settingsRow(L10n.text(.settingsLanguage, config: appState.config)) {
                    settingsMenu(
                        selection: appState.config.resolvedAppLanguage.settingsLabel,
                        options: AppLanguage.allCases.map(\.settingsLabel)
                    ) { label in
                        guard let language = AppLanguage.allCases.first(where: { $0.settingsLabel == label }) else { return }
                        controller.updateConfig { $0.appLanguage = language.rawValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(L10n.text(.settingsLaunchAtLogin, config: appState.config)) {
                    settingsSwitch(isOn: appState.config.launchAtLogin) { newValue in
                        controller.updateConfig { $0.launchAtLogin = newValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(L10n.text(.settingsOpenDashboardOnLaunch, config: appState.config)) {
                    settingsSwitch(isOn: appState.config.openDashboardOnLaunch) { newValue in
                        controller.updateConfig { $0.openDashboardOnLaunch = newValue }
                    }
                }
            }

            permissionsSection

            settingsSection(L10n.text(.settingsDataSection, config: appState.config)) {
                HStack(spacing: MuesliTheme.spacing12) {
                    actionButton(L10n.text(.settingsClearDictationHistory, config: appState.config), role: .destructive) {
                        pendingDataDestruction = .dictations
                    }
                    actionButton(L10n.text(.settingsClearMeetingHistory, config: appState.config), role: .destructive) {
                        pendingDataDestruction = .meetings
                    }
                    .disabled(controller.isMeetingRecording())
                    .help(L10n.text(.settingsStopRecordingBeforeClearing, config: appState.config))
                }
            }
        }
    }

    private var dictationSettingsPane: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
            settingsSection(L10n.text(.settingsTranscriptionSection, config: appState.config)) {
                settingsRow(L10n.text(.settingsDictationModel, config: appState.config)) {
                    settingsMenu(
                        selection: appState.selectedBackend.label,
                        options: dictationBackendOptions.map(\.label)
                    ) { label in
                        if let option = dictationBackendOptions.first(where: { $0.label == label }) {
                            controller.selectBackend(option)
                        }
                    }
                }
                if appState.selectedBackend.backend == BackendOption.cohereTranscribe.backend {
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(L10n.text(.settingsCohereLanguage, config: appState.config)) {
                        settingsMenu(
                            selection: selectedCohereLanguage.label,
                            options: CohereTranscribeLanguage.allCases.map(\.label)
                        ) { label in
                            guard let language = CohereTranscribeLanguage.allCases.first(where: { $0.label == label }) else { return }
                            controller.selectCohereLanguage(language)
                        }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(L10n.text(.settingsAiTranscriptCleanup, config: appState.config)) {
                    settingsSwitch(isOn: appState.config.enablePostProcessor) { newValue in
                        controller.setPostProcessorEnabled(newValue)
                    }
                }
                if appState.config.enablePostProcessor && !downloadedPostProcOptions.isEmpty {
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(L10n.text(.settingsCleanupModel, config: appState.config)) {
                        let selection = downloadedPostProcOptions.contains(where: { $0.id == appState.activePostProcessor.id })
                            ? appState.activePostProcessor.label
                            : (downloadedPostProcOptions.first?.label ?? "")
                        settingsMenu(
                            selection: selection,
                            options: downloadedPostProcOptions.map(\.label)
                        ) { label in
                            if let option = downloadedPostProcOptions.first(where: { $0.label == label }) {
                                controller.selectPostProcessor(option)
                            }
                        }
                    }
                } else if appState.config.enablePostProcessor {
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(L10n.text(.settingsCleanupModel, config: appState.config)) {
                        Text(L10n.text(.settingsDownloadCleanupModelHint, config: appState.config))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MuesliTheme.textTertiary)
                            .multilineTextAlignment(.trailing)
                            .frame(width: controlWidth, alignment: .trailing)
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(L10n.text(.settingsAppContext, config: appState.config)) {
                    settingsSwitch(isOn: appState.config.enableScreenContext) { newValue in
                        controller.updateConfig { $0.enableScreenContext = newValue }
                    }
                }
                Text(sharedContextDescription)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .padding(.horizontal, MuesliTheme.spacing16)
            }
        }
    }

    private var meetingsSettingsPane: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
            settingsSection(L10n.text(.settingsMeetingTranscriptionSection, config: appState.config)) {
                settingsRow(L10n.text(.settingsMeetingModel, config: appState.config)) {
                    settingsMenu(
                        selection: appState.selectedMeetingTranscriptionBackend.label,
                        options: meetingBackendOptions.map(\.label)
                    ) { label in
                        if let option = meetingBackendOptions.first(where: { $0.label == label }) {
                            controller.selectMeetingTranscriptionBackend(option)
                        }
                    }
                }
                if appState.selectedMeetingTranscriptionBackend.backend == BackendOption.cohereTranscribe.backend {
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(L10n.text(.settingsCohereLanguage, config: appState.config)) {
                        settingsMenu(
                            selection: selectedCohereLanguage.label,
                            options: CohereTranscribeLanguage.allCases.map(\.label)
                        ) { label in
                            guard let language = CohereTranscribeLanguage.allCases.first(where: { $0.label == label }) else { return }
                            controller.selectCohereLanguage(language)
                        }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(L10n.text(.settingsMeetingContext, config: appState.config)) {
                    settingsSwitch(isOn: appState.config.enableScreenContext) { newValue in
                        controller.updateConfig { $0.enableScreenContext = newValue }
                    }
                }
                Text(sharedContextDescription)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .padding(.horizontal, MuesliTheme.spacing16)
            }

            settingsSection(L10n.text(.settingsMeetingSummariesSection, config: appState.config)) {
                settingsRow(L10n.text(.settingsSummaryBackend, config: appState.config), controlWidth: meetingControlWidth) {
                    settingsMenu(
                        selection: appState.selectedMeetingSummaryBackend.label,
                        options: MeetingSummaryBackendOption.all.map(\.label)
                    ) { label in
                        if let option = MeetingSummaryBackendOption.all.first(where: { $0.label == label }) {
                            controller.selectMeetingSummaryBackend(option)
                        }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)

                if appState.selectedMeetingSummaryBackend == .chatGPT {
                    settingsRow(L10n.text(.settingsAccount, config: appState.config), controlWidth: meetingControlWidth) {
                        chatGPTAccountControl
                    }
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(L10n.text(.settingsModel, config: appState.config), controlWidth: meetingControlWidth) {
                        settingsModelMenu(
                            currentModel: appState.config.chatGPTModel,
                            presets: SummaryModelPreset.chatGPTModels
                        ) { val in controller.updateConfig { $0.chatGPTModel = val } }
                    }
                } else if appState.selectedMeetingSummaryBackend == .openAI {
                    settingsRow(L10n.text(.settingsApiKey, config: appState.config), controlWidth: meetingControlWidth) {
                        PastableSecureField(
                            text: appState.config.openAIAPIKey,
                            placeholder: "sk-...",
                            onChange: { val in controller.updateConfig { $0.openAIAPIKey = val } }
                        )
                        .frame(height: 22)
                    }
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(L10n.text(.settingsModel, config: appState.config), controlWidth: meetingControlWidth) {
                        settingsModelMenu(
                            currentModel: appState.config.openAIModel,
                            presets: SummaryModelPreset.openAIModels
                        ) { val in controller.updateConfig { $0.openAIModel = val } }
                    }
                    keyStatusRow(key: appState.config.openAIAPIKey)
                } else {
                    settingsRow(L10n.text(.settingsApiKey, config: appState.config), controlWidth: meetingControlWidth) {
                        PastableSecureField(
                            text: appState.config.openRouterAPIKey,
                            placeholder: "sk-or-...",
                            onChange: { val in controller.updateConfig { $0.openRouterAPIKey = val } }
                        )
                        .frame(height: 22)
                    }
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(L10n.text(.settingsFreeModel, config: appState.config), controlWidth: meetingControlWidth) {
                        openRouterFreeModelMenu
                    }
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(L10n.text(.settingsCustomModelID, config: appState.config), controlWidth: meetingControlWidth) {
                        settingsModelTextField(
                            currentModel: appState.config.openRouterModel,
                            placeholder: "provider/model or openrouter/free"
                        ) { val in controller.updateConfig { $0.openRouterModel = val } }
                    }
                    keyStatusRow(key: appState.config.openRouterAPIKey)
                }

                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(L10n.text(.settingsDefaultTemplate, config: appState.config), controlWidth: meetingControlWidth) {
                    meetingTemplateMenu(selectionID: appState.config.defaultMeetingTemplateID) { id in
                        controller.updateDefaultMeetingTemplate(id: id)
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(L10n.text(.settingsTemplates, config: appState.config), controlWidth: meetingControlWidth) {
                    actionButton(L10n.text(.meetingsManageTemplates, config: appState.config)) {
                        controller.showMeetingTemplatesManager()
                    }
                }
            }

            settingsSection(L10n.text(.settingsRecordingSection, config: appState.config)) {
                settingsRow(L10n.text(.settingsAutoRecordCalendarMeetings, config: appState.config)) {
                    settingsSwitch(isOn: appState.config.autoRecordMeetings) { newValue in
                        controller.updateConfig { $0.autoRecordMeetings = newValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(L10n.text(.settingsAutoRecordQuickNotes, config: appState.config)) {
                    settingsSwitch(isOn: appState.config.autoRecordQuickNotes) { newValue in
                        controller.updateConfig { $0.autoRecordQuickNotes = newValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(L10n.text(.settingsNotifyWhenMeetingDetected, config: appState.config)) {
                    settingsSwitch(isOn: appState.config.showMeetingDetectionNotification) { newValue in
                        controller.updateConfig { $0.showMeetingDetectionNotification = newValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(L10n.text(.settingsSaveMeetingRecording, config: appState.config)) {
                    settingsMenu(
                        selection: recordingSaveLabel(for: appState.config.meetingRecordingSavePolicy),
                        options: MeetingRecordingSavePolicy.allCases.map(recordingSaveLabel(for:))
                    ) { label in
                        guard let policy = recordingSavePolicy(for: label) else { return }
                        controller.updateConfig { $0.meetingRecordingSavePolicy = policy }
                    }
                }
            }

            settingsSection(L10n.text(.settingsAdvancedSection, config: appState.config)) {
                settingsRow(L10n.text(.settingsEnablePostMeetingHook, config: appState.config)) {
                    settingsSwitch(isOn: appState.config.meetingHookEnabled) { newValue in
                        controller.updateConfig { $0.meetingHookEnabled = newValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(L10n.text(.settingsHookScript, config: appState.config)) {
                    meetingHookPathPicker
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(L10n.text(.settingsTimeout, config: appState.config)) {
                    Stepper(
                        value: Binding(
                            get: { max(appState.config.meetingHookTimeoutSeconds, 1) },
                            set: { newValue in
                                controller.updateConfig { $0.meetingHookTimeoutSeconds = max(newValue, 1) }
                            }
                        ),
                        in: 1...600
                    ) {
                        Text(L10n.text(.settingsSeconds(count: max(appState.config.meetingHookTimeoutSeconds, 1)), config: appState.config))
                            .font(MuesliTheme.body())
                            .foregroundStyle(MuesliTheme.textPrimary)
                    }
                }
                Text(L10n.text(.settingsAdvancedHookDescription, config: appState.config))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .padding(.horizontal, MuesliTheme.spacing16)
            }

            settingsSection(L10n.text(.settingsCalendarSection, config: appState.config)) {
                localCalendarsControl

                Divider().background(MuesliTheme.surfaceBorder)
                    .padding(.top, MuesliTheme.spacing12)
                settingsRow(L10n.text(.settingsGoogleCalendar, config: appState.config)) {
                    googleCalendarControl
                }
            }
        }
    }

    private var appearanceSettingsPane: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
            settingsSection(L10n.text(.settingsFloatingIndicatorSection, config: appState.config)) {
                settingsRow(L10n.text(.settingsShowFloatingIndicator, config: appState.config)) {
                    settingsSwitch(isOn: appState.config.showFloatingIndicator) { newValue in
                        controller.updateConfig { $0.showFloatingIndicator = newValue }
                        controller.refreshIndicatorVisibility()
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(L10n.text(.settingsIndicatorPosition, config: appState.config)) {
                    let isCustom = appState.config.indicatorAnchor == .custom
                    let selection = isCustom ? customIndicatorPositionLabel : appState.config.indicatorAnchor.label
                    let options = (isCustom ? [customIndicatorPositionLabel] : [])
                        + IndicatorAnchor.allCases.filter { $0 != .custom }.map(\.label)
                    settingsMenu(
                        selection: selection,
                        options: options
                    ) { label in
                        if label == customIndicatorPositionLabel { return }
                        guard let anchor = IndicatorAnchor.allCases.first(where: { $0.label == label }) else { return }
                        controller.updateConfig { $0.indicatorAnchor = anchor }
                        controller.refreshIndicatorVisibility()
                    }
                }
            }

            settingsSection(L10n.text(.settingsAppearanceSection, config: appState.config)) {
                settingsRow(L10n.text(.settingsTheme, config: appState.config)) {
                    themePresetPicker
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(L10n.text(.settingsDarkMode, config: appState.config)) {
                    settingsSwitch(isOn: appState.config.darkMode) { newValue in
                        controller.updateConfig { $0.darkMode = newValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(L10n.text(.settingsMenuBarIcon, config: appState.config)) {
                    menuBarIconPicker
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(L10n.text(.settingsAccentColor, config: appState.config)) {
                    glassTintPicker
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(L10n.text(.settingsPlaySoundEffects, config: appState.config)) {
                    settingsSwitch(isOn: appState.config.soundEnabled) { newValue in
                        controller.updateConfig { $0.soundEnabled = newValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(L10n.text(.settingsShowNextMeetingInMenuBar, config: appState.config)) {
                    settingsSwitch(isOn: appState.config.showNextMeetingInMenuBar) { newValue in
                        controller.updateConfig { $0.showNextMeetingInMenuBar = newValue }
                    }
                }
            }

            if appState.config.maraudersMapUnlocked {
                settingsSection(L10n.text(.settingsMaraudersMapSection, config: appState.config)) {
                    settingsRow(L10n.text(.settingsMeetingCountdownAudio, config: appState.config)) {
                        maraudersMapControl
                    }
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow("") {
                        Button {
                            SoundController.stopMaraudersMapClip()
                            isPreviewingClip = false
                            controller.resetMaraudersMap()
                        } label: {
                            Text(L10n.text(.settingsMischiefManaged, config: appState.config))
                                .font(.system(size: 11))
                                .foregroundColor(MuesliTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var glassTintPicker: some View {
        HStack(spacing: 6) {
            ForEach(Self.accentPresets, id: \.hex) { preset in
                let isSelected = appState.config.recordingColorHex.lowercased() == preset.hex
                Button {
                    controller.updateConfig { $0.recordingColorHex = preset.hex }
                } label: {
                    Circle()
                        .fill(Color(hex: preset.hex))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(isSelected ? 0.9 : 0), lineWidth: 2)
                        )
                        .overlay(
                            Circle().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(preset.name)
            }
        }
    }

    private var themePresetPicker: some View {
        HStack(spacing: 8) {
            ForEach(ThemePreset.allCases, id: \.self) { preset in
                let isSelected = appState.config.resolvedThemePreset == preset
                Button {
                    controller.updateConfig { $0.themePreset = preset.rawValue }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        themePreviewStrip(for: preset)
                        Text(themePresetLabel(preset))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isSelected ? MuesliTheme.textPrimary : MuesliTheme.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(6)
                    .frame(width: 66, alignment: .leading)
                    .background(isSelected ? MuesliTheme.surfaceSelected.opacity(0.65) : MuesliTheme.surfacePrimary.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                            .strokeBorder(
                                isSelected ? MuesliTheme.accent.opacity(0.45) : MuesliTheme.surfaceBorder,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func themePreviewStrip(for preset: ThemePreset) -> some View {
        let palette = MuesliTheme.palette(for: preset)
        return HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: palette.backgroundBase.light))
                .frame(width: 14, height: 18)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: palette.backgroundRaised.light))
                .frame(width: 14, height: 18)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: palette.surfacePrimary.light))
                .frame(width: 14, height: 18)
        }
    }

    private func themePresetLabel(_ preset: ThemePreset) -> String {
        switch preset {
        case .warm:
            return L10n.text(.settingsThemeWarm, config: appState.config)
        case .neutral:
            return L10n.text(.settingsThemeNeutral, config: appState.config)
        case .graphite:
            return L10n.text(.settingsThemeGraphite, config: appState.config)
        }
    }

    private var menuBarIconPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(MenuBarIconRenderer.options, id: \.id) { option in
                    let isSelected = appState.config.menuBarIcon == option.id
                    Button {
                        controller.updateConfig { $0.menuBarIcon = option.id }
                    } label: {
                        Group {
                            if option.id == "muesli",
                               let img = MenuBarIconRenderer.make(choice: "muesli") {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: option.id)
                                    .font(.system(size: 12))
                            }
                        }
                        .foregroundStyle(isSelected ? MuesliTheme.accent : MuesliTheme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isSelected ? MuesliTheme.surfaceSelected : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.white.opacity(isSelected ? 0.3 : 0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(option.label)
                }
            }
        }
    }

    @ViewBuilder
    private var chatGPTAccountControl: some View {
        if appState.isChatGPTAuthenticated {
            Button {
                controller.signOutChatGPT()
            } label: {
                HStack(spacing: 5) {
                    OpenAILogoShape()
                        .fill(.white)
                        .frame(width: 10, height: 10)
                    Text(L10n.text(.settingsSignedInSignOut, config: appState.config))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(MuesliTheme.success)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
            .buttonStyle(.plain)
        } else if isSigningInChatGPT {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.text(.settingsSigningIn, config: appState.config))
                    .font(.system(size: 11))
                    .foregroundStyle(MuesliTheme.textSecondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    isSigningInChatGPT = true
                    chatGPTSignInError = nil
                    Task {
                        let error = await controller.signInWithChatGPT()
                        isSigningInChatGPT = false
                        chatGPTSignInError = error
                    }
                } label: {
                    HStack(spacing: 5) {
                        OpenAILogoShape()
                            .fill(.white)
                            .frame(width: 10, height: 10)
                        Text(L10n.text(.settingsSignInWithChatGPT, config: appState.config))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(MuesliTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                }
                .buttonStyle(.plain)

                if let chatGPTSignInError {
                    Text(chatGPTSignInError)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private var localCalendarsControl: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            Text(L10n.text(.settingsLocalCalendars, config: appState.config))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MuesliTheme.textSecondary)
            Text(L10n.text(.settingsLocalCalendarsHint, config: appState.config))
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)

            if appState.availableLocalCalendars.isEmpty {
                Text(L10n.text(.settingsNoLocalCalendarsFound, config: appState.config))
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(appState.availableLocalCalendars.enumerated()), id: \.element.id) { index, calendar in
                        localCalendarRow(calendar)
                        if index < appState.availableLocalCalendars.count - 1 {
                            Divider().background(MuesliTheme.surfaceBorder)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func localCalendarRow(_ calendar: LocalCalendarInfo) -> some View {
        let isEnabled = !appState.config.hiddenLocalCalendarIDs.contains(calendar.id)
        HStack(alignment: .center, spacing: MuesliTheme.spacing12) {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(calendarSwatchColor(calendar.colorHex))
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(calendar.title)
                        .font(MuesliTheme.body())
                        .foregroundStyle(MuesliTheme.textPrimary)
                    if let sourceTitle = calendar.sourceTitle, !sourceTitle.isEmpty {
                        Text(sourceTitle)
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }
                }
            }

            Spacer(minLength: 12)

            Toggle(
                "",
                isOn: Binding(
                    get: { isEnabled },
                    set: { controller.setLocalCalendarEnabled(calendar.id, isEnabled: $0) }
                )
            )
            .toggleStyle(.switch)
            .tint(MuesliTheme.accent)
            .labelsHidden()
        }
        .frame(minHeight: 34)
    }

    private func calendarSwatchColor(_ hex: String?) -> Color {
        guard let hex, !hex.isEmpty else {
            return MuesliTheme.textTertiary.opacity(0.35)
        }
        return Color(hex: hex)
    }

    @ViewBuilder
    private var googleCalendarControl: some View {
        if appState.isGoogleCalendarAuthenticated {
            Button {
                controller.signOutGoogleCalendar()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                    Text(L10n.text(.settingsConnectedDisconnect, config: appState.config))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(MuesliTheme.success)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
            .buttonStyle(.plain)
        } else if isSigningInGoogleCal {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.text(.settingsConnecting, config: appState.config))
                    .font(.system(size: 11))
                    .foregroundStyle(MuesliTheme.textSecondary)
            }
        } else if !appState.isGoogleCalendarVerified {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(L10n.text(.settingsConnectGoogleCalendar, config: appState.config))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(MuesliTheme.textTertiary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))

                Text(L10n.text(.settingsGoogleOAuthPending, config: appState.config))
                    .font(.system(size: 10))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
        } else if !appState.isGoogleCalendarAvailable {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(L10n.text(.settingsConnectGoogleCalendar, config: appState.config))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(MuesliTheme.textTertiary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))

                Text(L10n.text(.settingsGoogleCalendarUnavailable, config: appState.config))
                    .font(.system(size: 10))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    isSigningInGoogleCal = true
                    googleCalSignInError = nil
                    Task {
                        let error = await controller.signInWithGoogleCalendar()
                        isSigningInGoogleCal = false
                        googleCalSignInError = error
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                    Text(L10n.text(.settingsConnectGoogleCalendar, config: appState.config))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(MuesliTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                }
                .buttonStyle(.plain)

                if let googleCalSignInError {
                    Text(googleCalSignInError)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
    }

    private var maraudersMapControl: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            settingsMenu(
                selection: SoundController.labelForClip(
                    id: appState.config.maraudersMapAudioClip,
                    customPath: appState.config.maraudersMapCustomAudioPath
                ),
                options: SoundController.maraudersMapClipLabels
            ) { label in
                if label == "Custom\u{2026}" {
                    pickCustomAudioFile()
                } else if let preset = SoundController.maraudersMapPresets
                    .first(where: { $0.label == label }) {
                    SoundController.stopMaraudersMapClip()
                    isPreviewingClip = false
                    controller.updateConfig {
                        $0.maraudersMapAudioClip = preset.id
                        $0.maraudersMapCustomAudioPath = nil
                    }
                    controller.updateMaraudersMapAudioClip()
                }
            }
            Button {
                if isPreviewingClip {
                    SoundController.stopMaraudersMapClip()
                    isPreviewingClip = false
                } else {
                    SoundController.playMaraudersMapClip(
                        id: appState.config.maraudersMapAudioClip,
                        customPath: appState.config.maraudersMapCustomAudioPath
                    ) {
                        isPreviewingClip = false
                    }
                    isPreviewingClip = true
                }
            } label: {
                Image(systemName: isPreviewingClip ? "stop.fill" : "play.fill")
                    .font(.system(size: 11))
                    .foregroundColor(MuesliTheme.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
    }

    // MARK: - Marauder's Map

    private func pickCustomAudioFile() {
        let panel = NSOpenPanel()
        panel.title = L10n.text(.settingsChooseAudioClip, config: appState.config)
        panel.allowedContentTypes = [.mp3, .mpeg4Audio, .wav, .aiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let appSupportBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fputs("[muesli-native] Could not resolve Application Support directory\n", stderr)
            return
        }

        do {
            let supportDir = appSupportBase
                .appendingPathComponent(Bundle.main.infoDictionary?["MuesliSupportDirectoryName"] as? String ?? "Muesli")
            let destPath = try SoundController.importCustomClip(from: url, supportDir: supportDir)
            controller.updateConfig {
                $0.maraudersMapAudioClip = SoundController.customClipID
                $0.maraudersMapCustomAudioPath = destPath
            }
            controller.updateMaraudersMapAudioClip()
        } catch {
            fputs("[muesli-native] Failed to import custom audio: \(error)\n", stderr)
        }
    }

    private func pickMeetingHookFile() {
        let panel = NSOpenPanel()
        panel.title = L10n.text(.settingsChooseHookScriptTitle, config: appState.config)
        panel.prompt = L10n.text(.settingsChooseScriptPrompt, config: appState.config)
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = preferredMeetingHookDirectoryURL()

        presentOpenPanel(panel) { url in
            controller.updateConfig { $0.meetingHookPath = url.standardizedFileURL.path }
        }
    }

    private func preferredMeetingHookDirectoryURL() -> URL {
        let configuredPath = appState.config.meetingHookPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configuredPath.isEmpty {
            let configuredURL = URL(fileURLWithPath: configuredPath).standardizedFileURL
            let parentDirectory = configuredURL.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parentDirectory.path) {
                return parentDirectory
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    private func presentOpenPanel(_ panel: NSOpenPanel, onPick: @escaping (URL) -> Void) {
        NSApp.activate()
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                onPick(url)
            }
        } else {
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                onPick(url)
            }
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        settingsSection(L10n.text(.settingsPermissionsSection, config: appState.config)) {
            permissionStatusRow(
                L10n.text(.settingsPermissionMicrophone, config: appState.config),
                granted: micGranted,
                action: { AVCaptureDevice.requestAccess(for: .audio) { _ in } },
                pane: "Privacy_Microphone"
            )
            Divider().background(MuesliTheme.surfaceBorder)
            permissionStatusRow(
                L10n.text(.settingsPermissionAccessibility, config: appState.config),
                granted: accessibilityGranted,
                action: {
                    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                    AXIsProcessTrustedWithOptions(opts)
                },
                pane: "Privacy_Accessibility"
            )
            Divider().background(MuesliTheme.surfaceBorder)
            permissionStatusRow(
                L10n.text(.settingsPermissionInputMonitoring, config: appState.config),
                granted: inputMonitoringGranted,
                action: {
                    if !CGRequestListenEventAccess() {
                        openPrivacyPane("Privacy_ListenEvent")
                    }
                },
                pane: "Privacy_ListenEvent"
            )
            Divider().background(MuesliTheme.surfaceBorder)
            permissionStatusRow(
                L10n.text(.settingsPermissionScreenRecording, config: appState.config),
                granted: screenRecordingGranted,
                action: { CGRequestScreenCaptureAccess() },
                pane: "Privacy_ScreenCapture"
            )
            if appState.config.useCoreAudioTap {
                Divider().background(MuesliTheme.surfaceBorder)
                permissionStatusRow(
                    L10n.text(.settingsPermissionSystemAudio, config: appState.config),
                    granted: systemAudioGranted,
                    action: {
                        Task { await CoreAudioSystemRecorder.requestSystemAudioAccess() }
                    },
                    pane: "Privacy_ScreenCapture"
                )
            }
        }
    }

    @ViewBuilder
    private func permissionStatusRow(_ name: String, granted: Bool, action: @escaping () -> Void, pane: String) -> some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(granted ? MuesliTheme.success : MuesliTheme.recording)
                    .frame(width: 8, height: 8)
                Text(name)
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textPrimary)
            }
            Spacer()
            if granted {
                Text(L10n.text(.settingsGranted, config: appState.config))
                    .font(.system(size: 11))
                    .foregroundStyle(MuesliTheme.success)
            } else {
                Button(L10n.text(.settingsGrant, config: appState.config)) {
                    action()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MuesliTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(MuesliTheme.accentSubtle)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
            Button {
                openPrivacyPane(pane)
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 11))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .help(L10n.text(.settingsOpenInSystemSettings, config: appState.config))
        }
        .frame(minHeight: 32)
    }

    private func openPrivacyPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startPermissionPolling() {
        refreshPermissionStatuses()
        permissionPollTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            refreshPermissionStatuses()
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionPollTimer = timer
    }

    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    private func refreshPermissionStatuses() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        refreshSystemAudioPermissionIfNeeded()
    }

    private func refreshSystemAudioPermissionIfNeeded() {
        guard appState.config.useCoreAudioTap, !isCheckingSystemAudioPermission else { return }
        isCheckingSystemAudioPermission = true

        Task {
            let granted = await Task.detached(priority: .utility) {
                CoreAudioSystemRecorder.checkSystemAudioPermission()
            }.value
            await MainActor.run {
                self.systemAudioGranted = granted
                self.isCheckingSystemAudioPermission = false
            }
        }
    }

    // MARK: - Layout Primitives

    @ViewBuilder
    private func settingsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MuesliTheme.textTertiary)
                .textCase(.uppercase)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(MuesliTheme.spacing16)
            .background(MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    /// Standardized row: label on left, control on right.
    /// Controls share a fixed-width column so they all right-align consistently.
    @ViewBuilder
    private func settingsRow(_ label: String, controlWidth rowControlWidth: CGFloat? = nil, @ViewBuilder control: () -> some View) -> some View {
        let width = rowControlWidth ?? controlWidth
        HStack(alignment: .center) {
            Text(label)
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textPrimary)
                .layoutPriority(1)
            Spacer(minLength: 20)
            ZStack(alignment: .trailing) {
                // Invisible spacer forces the ZStack to exactly controlWidth
                Color.clear.frame(width: width, height: 1)
                control()
                    .frame(maxWidth: width)
            }
        }
        .frame(minHeight: 32)
    }

    // MARK: - Controls

    @ViewBuilder
    private func settingsSwitch(isOn: Bool, onChange: @escaping (Bool) -> Void) -> some View {
        HStack {
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { onChange($0) }))
                .toggleStyle(.switch)
                .tint(MuesliTheme.accent)
                .labelsHidden()
        }
    }

    @ViewBuilder
    private func settingsMenu(selection: String, options: [String], onChange: @escaping (String) -> Void) -> some View {
        FixedWidthPopUp(selection: selection, options: options, onChange: onChange)
            .frame(height: 24)
    }

    @ViewBuilder
    private var meetingHookPathPicker: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MuesliTheme.textTertiary)

                if appState.config.meetingHookPath.isEmpty {
                    Text(L10n.text(.settingsChooseScriptEllipsis, config: appState.config))
                        .font(.system(size: 12))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .lineLimit(1)
                } else {
                    Text(appState.config.meetingHookPath)
                        .font(.system(size: 12))
                        .foregroundStyle(MuesliTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
            .help(appState.config.meetingHookPath.isEmpty ? L10n.text(.settingsNoHookScriptSelected, config: appState.config) : appState.config.meetingHookPath)

            if !appState.config.meetingHookPath.isEmpty {
                Button {
                    controller.updateConfig { $0.meetingHookPath = "" }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(L10n.text(.settingsClearHookScript, config: appState.config))
            }

            Button {
                pickMeetingHookFile()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(MuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                            .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(L10n.text(.settingsChooseHookScript, config: appState.config))
        }
    }

    @ViewBuilder
    private func meetingTemplateMenu(selectionID: String, onChange: @escaping (String) -> Void) -> some View {
        let autoTarget = controller.effectiveAutoMeetingTemplate()
        let autoLabel = autoTarget.id == MeetingTemplates.autoID
            ? L10n.text(.settingsDefaultTemplateAuto, config: appState.config)
            : "\(L10n.text(.settingsDefaultTemplateAuto, config: appState.config)) (\(autoTarget.title))"
        let allItems: [(id: String, label: String)] = {
            var items: [(String, String)] = [(MeetingTemplates.autoID, autoLabel)]
            items += controller.customMeetingTemplates().map { ($0.id, $0.name) }
            items += controller.visibleBuiltInMeetingTemplates().map { ($0.id, $0.title) }
            return items
        }()
        let selectedLabel = allItems.first(where: { $0.id == selectionID })?.label ?? autoLabel
        FixedWidthPopUp(
            selection: selectedLabel,
            options: allItems.map(\.label),
            onSelectIndex: { index in
                guard index >= 0 && index < allItems.count else { return }
                onChange(allItems[index].id)
            }
        )
        .frame(height: 24)
    }

    @ViewBuilder
    private func settingsModelMenu(currentModel: String, presets: [SummaryModelPreset], onChange: @escaping (String) -> Void) -> some View {
        let menuPresets = SummaryModelPreset.menuPresets(presets, currentModel: currentModel)
        let effectiveModel = currentModel.isEmpty ? (presets.first?.id ?? "") : currentModel
        let selectedLabel = menuPresets.first(where: { $0.id == effectiveModel })?.label ?? menuPresets.first?.label ?? ""
        FixedWidthPopUp(
            selection: selectedLabel,
            options: menuPresets.map(\.label),
            onSelectIndex: { index in
                guard index >= 0 && index < menuPresets.count else { return }
                let selectedId = menuPresets[index].id
                onChange(selectedId == presets.first?.id ? "" : selectedId)
            }
        )
        .frame(height: 24)
    }

    @ViewBuilder
    private func settingsModelTextField(currentModel: String, placeholder: String, onChange: @escaping (String) -> Void) -> some View {
        PastableTextField(
            text: currentModel,
            placeholder: placeholder,
            onChange: { value in
                onChange(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        )
        .frame(height: 22)
    }

    @ViewBuilder
    private var openRouterFreeModelMenu: some View {
        if isLoadingOpenRouterFreeModels {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.text(.settingsLoadingModels, config: appState.config))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else if !openRouterFreeModels.isEmpty {
            settingsModelMenu(
                currentModel: appState.config.openRouterModel,
                presets: openRouterFreeModels
            ) { val in controller.updateConfig { $0.openRouterModel = val } }
        } else {
            HStack(spacing: 8) {
                if let openRouterFreeModelsError {
                    Text(openRouterFreeModelsError)
                        .font(.system(size: 11))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .lineLimit(1)
                }
                Button(L10n.text(.settingsLoadModels, config: appState.config)) {
                    loadOpenRouterFreeModels(force: true)
                }
                .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func loadOpenRouterFreeModelsIfNeeded() {
        guard openRouterFreeModels.isEmpty, !isLoadingOpenRouterFreeModels else { return }
        loadOpenRouterFreeModels(force: false)
    }

    private func loadOpenRouterFreeModels(force: Bool) {
        guard force || openRouterFreeModels.isEmpty else { return }
        isLoadingOpenRouterFreeModels = true
        openRouterFreeModelsError = nil

        Task {
            do {
                let url = URL(string: "https://openrouter.ai/api/v1/models?output_modalities=text")!
                let (data, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse,
                   !(200..<300).contains(httpResponse.statusCode) {
                    throw URLError(.badServerResponse)
                }
                let catalog = try JSONDecoder().decode(OpenRouterModelCatalog.self, from: data)
                let presets = OpenRouterModelCatalogFilter.freeTextSummaryPresets(from: catalog.data)

                await MainActor.run {
                    openRouterFreeModels = presets
                    openRouterFreeModelsError = presets.isEmpty ? "No free text models found" : nil
                    isLoadingOpenRouterFreeModels = false
                }
            } catch {
                await MainActor.run {
                    openRouterFreeModels = []
                    openRouterFreeModelsError = "Could not load"
                    isLoadingOpenRouterFreeModels = false
                }
            }
        }
    }

    @ViewBuilder
    private func keyStatusRow(key: String) -> some View {
        HStack(spacing: 6) {
            Spacer()
            Circle()
                .fill(key.isEmpty ? MuesliTheme.textTertiary : MuesliTheme.success)
                .frame(width: 6, height: 6)
            Text(
                key.isEmpty
                    ? L10n.text(.settingsNoApiKeyConfigured, config: appState.config)
                    : L10n.text(.settingsApiKeyConfigured, config: appState.config)
            )
                .font(.system(size: 11))
                .foregroundStyle(key.isEmpty ? MuesliTheme.textTertiary : MuesliTheme.success)
        }
        .frame(minHeight: 20)
    }

    @ViewBuilder
    private func actionButton(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        let isDestructive = role == .destructive
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isDestructive ? MuesliTheme.recording : MuesliTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, MuesliTheme.spacing16)
                .padding(.vertical, MuesliTheme.spacing8)
                .background(isDestructive ? MuesliTheme.recording.opacity(0.1) : MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .strokeBorder(
                            isDestructive ? MuesliTheme.recording.opacity(0.2) : MuesliTheme.surfaceBorder,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func recordingSaveLabel(for policy: MeetingRecordingSavePolicy) -> String {
        switch policy {
        case .never:
            return L10n.text(.settingsRecordingSaveNever, config: appState.config)
        case .prompt:
            return L10n.text(.settingsRecordingSavePrompt, config: appState.config)
        case .always:
            return L10n.text(.settingsRecordingSaveAlways, config: appState.config)
        }
    }

    private func recordingSavePolicy(for label: String) -> MeetingRecordingSavePolicy? {
        let policy = MeetingRecordingSavePolicy.allCases.first { recordingSaveLabel(for: $0) == label }
        if policy == nil {
            assertionFailure("Unexpected recording save label: \(label)")
        }
        return policy
    }
}

// MARK: - Pastable Secure Field (NSViewRepresentable)

/// NSSecureTextField subclass that handles Cmd+V/C/X/A without needing a standard Edit menu.
/// Required because the app runs as .accessory (no menu bar), so key equivalents
/// don't route to text fields by default.
class EditableNSSecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "v":
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
            case "c":
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
            case "x":
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return true }
            case "a":
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// NSPopUpButton wrapper that respects width constraints (SwiftUI Picker with .menu style ignores them).
struct FixedWidthPopUp: NSViewRepresentable {
    let selection: String
    let options: [String]
    /// Reports the selected index, avoiding label collision issues.
    let onSelectionIndex: (Int) -> Void

    init(selection: String, options: [String], onChange: @escaping (String) -> Void) {
        self.selection = selection
        self.options = options
        self.onSelectionIndex = { index in
            guard index >= 0 && index < options.count else { return }
            onChange(options[index])
        }
    }

    init(selection: String, options: [String], onSelectIndex: @escaping (Int) -> Void) {
        self.selection = selection
        self.options = options
        self.onSelectionIndex = onSelectIndex
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.removeAllItems()
        button.addItems(withTitles: options)
        button.selectItem(withTitle: selection)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let currentTitles = button.itemTitles
        if currentTitles != options {
            button.removeAllItems()
            button.addItems(withTitles: options)
        }
        if button.titleOfSelectedItem != selection {
            button.selectItem(withTitle: selection)
        }
        context.coordinator.onSelectionIndex = onSelectionIndex
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelectionIndex: onSelectionIndex) }

    class Coordinator: NSObject {
        var onSelectionIndex: (Int) -> Void
        init(onSelectionIndex: @escaping (Int) -> Void) { self.onSelectionIndex = onSelectionIndex }
        @objc func selectionChanged(_ sender: NSPopUpButton) {
            onSelectionIndex(sender.indexOfSelectedItem)
        }
    }
}

/// A text field that supports Cmd+V paste and masks the value when not focused.
struct PastableSecureField: NSViewRepresentable {
    let text: String
    let placeholder: String
    let onChange: (String) -> Void

    func makeNSView(context: Context) -> EditableNSSecureTextField {
        let field = EditableNSSecureTextField()
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 13)
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ nsView: EditableNSSecureTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let onChange: (String) -> Void

        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            onChange(field.stringValue)
        }
    }
}

/// Plain text field with the same accessory-app edit shortcuts as secure fields.
struct PastableTextField: NSViewRepresentable {
    let text: String
    let placeholder: String
    let onChange: (String) -> Void

    func makeNSView(context: Context) -> EditableNSTextField {
        let field = EditableNSTextField()
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 13)
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ nsView: EditableNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let onChange: (String) -> Void

        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            onChange(field.stringValue)
        }
    }
}

private extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        h = h.hasPrefix("#") ? String(h.dropFirst()) : h
        guard h.count == 6, let value = UInt64(h, radix: 16) else {
            self = .black; return
        }
        self = Color(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8)  & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255
        )
    }
}

private extension NSColor {
    func toHexString() -> String? {
        guard let rgb = usingColorSpace(.sRGB) else { return nil }
        let r = Int((rgb.redComponent   * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent  * 255).rounded())
        return String(format: "%02x%02x%02x", r, g, b)
    }
}
