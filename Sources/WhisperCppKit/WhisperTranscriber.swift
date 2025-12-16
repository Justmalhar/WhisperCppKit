import Foundation

public enum WhisperTranscriber {
    public static func transcribeFile(
        modelPath: String,
        audioPath: String,
        options: WhisperOptions = .init()
    ) throws -> [WhisperSegment] {
        let ctx = try WhisperContext(modelPath: modelPath, verbose: options.verbose)
        let pcm = try AudioDecoder.decodeToPCM16k(url: URL(fileURLWithPath: audioPath))
        return try ctx.transcribe(pcm16k: pcm, options: options)
    }

    public static func transcribeURL(
        modelPath: String,
        audioURL: URL,
        options: WhisperOptions = .init()
    ) throws -> [WhisperSegment] {
        let ctx = try WhisperContext(modelPath: modelPath, verbose: options.verbose)
        let pcm = try AudioDecoder.decodeToPCM16k(url: audioURL)
        return try ctx.transcribe(pcm16k: pcm, options: options)
    }
}