import Testing
@testable import MuesliNativeApp

@Suite("Settings panes")
struct SettingsPaneTests {
    @Test("settings panes use the reorganized order")
    func settingsPaneOrder() {
        #expect(SettingsPane.allCases == [
            .general,
            .voiceAndDictation,
            .meetings,
            .models,
            .appearance,
        ])
    }

    @Test("settings pane titles are localized in English")
    func settingsPaneTitlesEnglish() {
        var config = AppConfig()
        config.appLanguage = AppLanguage.english.rawValue

        #expect(SettingsPane.general.localizedTitle(config: config) == "General")
        #expect(SettingsPane.voiceAndDictation.localizedTitle(config: config) == "Voice & Dictation")
        #expect(SettingsPane.meetings.localizedTitle(config: config) == "Meetings")
        #expect(SettingsPane.models.localizedTitle(config: config) == "Models")
        #expect(SettingsPane.appearance.localizedTitle(config: config) == "Appearance")
    }

    @Test("settings pane titles are localized in Spanish")
    func settingsPaneTitlesSpanish() {
        var config = AppConfig()
        config.appLanguage = AppLanguage.spanish.rawValue

        #expect(SettingsPane.general.localizedTitle(config: config) == "General")
        #expect(SettingsPane.voiceAndDictation.localizedTitle(config: config) == "Voz y dictado")
        #expect(SettingsPane.meetings.localizedTitle(config: config) == "Reuniones")
        #expect(SettingsPane.models.localizedTitle(config: config) == "Modelos")
        #expect(SettingsPane.appearance.localizedTitle(config: config) == "Apariencia")
    }
}
