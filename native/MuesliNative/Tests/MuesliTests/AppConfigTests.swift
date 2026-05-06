import Foundation
import Testing
@testable import MuesliNativeApp

@Suite("AppConfig")
struct AppConfigLiveTranscriptTests {
    @Test("live meeting transcript is enabled by default")
    func liveTranscriptEnabledByDefault() {
        let config = AppConfig()
        #expect(config.enableLiveMeetingTranscript)
    }

    @Test("legacy config payloads default live meeting transcript to enabled")
    func legacyConfigDefaultsLiveTranscriptToEnabled() throws {
        let json = """
        {
          "meeting_transcription_backend": "whisper",
          "meeting_transcription_model": "small.en"
        }
        """

        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.enableLiveMeetingTranscript)
    }
}
