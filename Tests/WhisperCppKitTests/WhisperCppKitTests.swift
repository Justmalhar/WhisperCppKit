import XCTest
@testable import WhisperCppKit

final class WhisperCppKitTests: XCTestCase {
    func testPing() {
        WhisperCppKitSmokeTest.ping()
    }

    func testTranscribeIfConfigured() throws {
        let env = ProcessInfo.processInfo.environment

        let model = env["WHISPER_MODEL"] ?? env["WHISPER_MODEL_PATH"]
        let audio = env["WHISPER_AUDIO"] ?? env["WHISPER_AUDIO_PATH"]

        guard let model, let audio else {
            throw XCTSkip("Set WHISPER_MODEL/WHISPER_AUDIO (or *_PATH) to run integration transcription.")
        }

        var opts = WhisperOptions()
        opts.language = "en"
        opts.threads = 4

        let segs = try WhisperTranscriber.transcribeFile(
            modelPath: model,
            audioPath: audio,
            options: opts
        )
        print(segs)
        XCTAssertFalse(segs.isEmpty)
        XCTAssertTrue(segs.map(\.text).joined().count > 0)
    }
}