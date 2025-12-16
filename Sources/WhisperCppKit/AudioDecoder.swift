import Foundation
import AVFoundation

enum AudioDecoder {
    /// Decode any AVFoundation-supported audio to mono 16kHz Float32 PCM
    static func decodeToPCM16k(url: URL) throws -> [Float] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw WhisperError.audioDecodeFailed("Audio file not found: \(url.path)")
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw WhisperError.audioDecodeFailed(
                "AVAudioFile failed to open: \(url.path)\n" +
                "Reason: \(error.localizedDescription)\n" +
                "Tip: try re-encoding to m4a/aac or wav (16k/mono)."
            )
        }

        let inputFormat = file.processingFormat

        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw WhisperError.audioDecodeFailed("Failed to create output format")
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outFormat) else {
            throw WhisperError.audioDecodeFailed("Failed to create AVAudioConverter")
        }

        let inCapacity = AVAudioFrameCount(file.length)
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: inCapacity) else {
            throw WhisperError.audioDecodeFailed("Failed to allocate input buffer")
        }
        try file.read(into: inBuffer)

        let ratio = outFormat.sampleRate / inputFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(inBuffer.frameLength) * ratio + 1024)

        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity) else {
            throw WhisperError.audioDecodeFailed("Failed to allocate output buffer")
        }

        var didSupply = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if didSupply {
                outStatus.pointee = .endOfStream
                return nil
            } else {
                didSupply = true
                outStatus.pointee = .haveData
                return inBuffer
            }
        }

        var error: NSError?
        converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
        if let error {
            throw WhisperError.audioDecodeFailed(
                "AVAudioConverter failed for: \(url.path)\n" +
                "Reason: \(error.localizedDescription)"
            )
        }

        guard let channel = outBuffer.floatChannelData?[0] else {
            throw WhisperError.audioDecodeFailed("No floatChannelData")
        }
        let frames = Int(outBuffer.frameLength)
        return Array(UnsafeBufferPointer(start: channel, count: frames))
    }
}