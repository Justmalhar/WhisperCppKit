import Foundation
import WhisperCpp

public enum WhisperSwiftError: Error {
    case invalidUTF8
}

public final class Whisper {
    public init() {}

    // Placeholder: you’ll wrap whisper_init_from_file / whisper_full, etc.
    public func hello() -> String {
        // sanity check the module imports + links
        return "WhisperCpp linked ✅"
    }
}
