import Foundation
import WhisperCpp

public enum WhisperCppKitSmokeTest {
    public static func ping() {
        _ = whisper_context_default_params()
    }
}
