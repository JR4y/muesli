import Testing
@testable import MuesliNativeApp

@Suite("Meeting transcript display turn parser")
struct MeetingTranscriptDisplayTurnParserTests {
    @Test("parses You Others and Speaker labels")
    func parsesStandardTranscriptLines() throws {
        let turns = MeetingTranscriptDisplayTurnParser.parse(
            """
            [16:00:27] You: Hola
            [16:00:31] Others: Hello there
            [16:00:35] Speaker 1: Seguimos
            """
        )

        #expect(turns.count == 3)
        #expect(turns[0].speakerLabel == "You")
        #expect(turns[0].timestampLabel == "16:00:27")
        #expect(turns[0].style == .localSpeaker)
        #expect(turns[1].speakerLabel == "Others")
        #expect(turns[1].style == .remoteSpeaker)
        #expect(turns[2].speakerLabel == "Speaker 1")
        #expect(turns[2].style == .remoteSpeaker)
    }

    @Test("returns empty turns for empty transcript")
    func handlesEmptyTranscript() {
        let turns = MeetingTranscriptDisplayTurnParser.parse("  \n\n ")
        #expect(turns.isEmpty)
    }

    @Test("falls back safely for malformed lines")
    func fallsBackForMalformedLines() {
        let turns = MeetingTranscriptDisplayTurnParser.parse(
            """
            malformed transcript line
            [16:00:27] You: Hola
            """
        )

        #expect(turns.count == 2)
        #expect(turns[0].speakerLabel == "Transcript")
        #expect(turns[0].timestampLabel == nil)
        #expect(turns[0].style == .remoteSpeaker)
        #expect(turns[1].speakerLabel == "You")
    }
}
