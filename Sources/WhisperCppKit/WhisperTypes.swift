import Foundation

public struct WhisperSegment: Sendable, Equatable, Codable {
    public let index: Int
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let text: String

    public init(index: Int, startTime: TimeInterval, endTime: TimeInterval, text: String) {
        self.index = index
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

public struct WhisperOptions: Sendable {
    public var language: String? = nil           // e.g. "en"
    public var translateToEnglish: Bool = false  // translate -> English
    public var threads: Int = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)

    /// If true, do not suppress whisper.cpp / ggml logs.
    /// Default false = clean CLI output.
    public var verbose: Bool = false

    /// Called by whisper.cpp progress callback (typically 0..100).
    /// Note: may be invoked from non-main threads.
    public var onProgress: (@Sendable (Int32) -> Void)? = nil

    /// Called when whisper.cpp finalizes new segments.
    /// Note: may be invoked from non-main threads.
    public var onNewSegment: (@Sendable (WhisperSegment) -> Void)? = nil

    public init() {}
}

public enum WhisperError: Error, CustomStringConvertible {
    case failedToInitContext(modelPath: String)
    case whisperFailed(code: Int32)
    case audioDecodeFailed(String)

    public var description: String {
        switch self {
        case .failedToInitContext(let p): return "Failed to init whisper context from model: \(p)"
        case .whisperFailed(let c):       return "whisper_full failed with code: \(c)"
        case .audioDecodeFailed(let m):   return "Audio decode failed: \(m)"
        }
    }
}