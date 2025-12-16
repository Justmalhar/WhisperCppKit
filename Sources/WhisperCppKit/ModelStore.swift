import Foundation

public enum WhisperModel: String, CaseIterable {
    // IDs (stable for CLI + API)
    case tinyEn        = "tiny.en"
    case tinyMulti     = "tiny"

    case baseEn        = "base.en"
    case baseMulti     = "base"

    case smallEn       = "small.en"
    case smallMulti    = "small"

    case mediumEn      = "medium.en"
    case mediumMulti   = "medium"

    case largeV1       = "large-v1"
    case largeV2       = "large-v2"
    case largeV3       = "large-v3"
    case largeV3Turbo  = "large-v3-turbo"

    // Quantized (smaller downloads)
    case tinyEnQ5_1    = "tiny.en-q5_1"
    case tinyEnQ8_0    = "tiny.en-q8_0"
    case tinyQ5_1      = "tiny-q5_1"
    case tinyQ8_0      = "tiny-q8_0"

    case baseEnQ5_1    = "base.en-q5_1"
    case baseEnQ8_0    = "base.en-q8_0"
    case baseQ5_1      = "base-q5_1"
    case baseQ8_0      = "base-q8_0"

    case smallEnQ5_1   = "small.en-q5_1"
    case smallEnQ8_0   = "small.en-q8_0"
    case smallQ5_1     = "small-q5_1"
    case smallQ8_0     = "small-q8_0"

    case mediumEnQ5_0  = "medium.en-q5_0"
    case mediumEnQ8_0  = "medium.en-q8_0"
    case mediumQ5_0    = "medium-q5_0"
    case mediumQ8_0    = "medium-q8_0"

    case largeV2Q5_0   = "large-v2-q5_0"
    case largeV2Q8_0   = "large-v2-q8_0"
    case largeV3Q5_0   = "large-v3-q5_0"
    case largeV3TurboQ5_0 = "large-v3-turbo-q5_0"
    case largeV3TurboQ8_0 = "large-v3-turbo-q8_0"

    public var filename: String {
        switch self {
        case .tinyEn: "ggml-tiny.en.bin"
        case .tinyMulti: "ggml-tiny.bin"

        case .baseEn: "ggml-base.en.bin"
        case .baseMulti: "ggml-base.bin"

        case .smallEn: "ggml-small.en.bin"
        case .smallMulti: "ggml-small.bin"

        case .mediumEn: "ggml-medium.en.bin"
        case .mediumMulti: "ggml-medium.bin"

        case .largeV1: "ggml-large-v1.bin"
        case .largeV2: "ggml-large-v2.bin"
        case .largeV3: "ggml-large-v3.bin"
        case .largeV3Turbo: "ggml-large-v3-turbo.bin"

        case .tinyEnQ5_1: "ggml-tiny.en-q5_1.bin"
        case .tinyEnQ8_0: "ggml-tiny.en-q8_0.bin"
        case .tinyQ5_1: "ggml-tiny-q5_1.bin"
        case .tinyQ8_0: "ggml-tiny-q8_0.bin"

        case .baseEnQ5_1: "ggml-base.en-q5_1.bin"
        case .baseEnQ8_0: "ggml-base.en-q8_0.bin"
        case .baseQ5_1: "ggml-base-q5_1.bin"
        case .baseQ8_0: "ggml-base-q8_0.bin"

        case .smallEnQ5_1: "ggml-small.en-q5_1.bin"
        case .smallEnQ8_0: "ggml-small.en-q8_0.bin"
        case .smallQ5_1: "ggml-small-q5_1.bin"
        case .smallQ8_0: "ggml-small-q8_0.bin"

        case .mediumEnQ5_0: "ggml-medium.en-q5_0.bin"
        case .mediumEnQ8_0: "ggml-medium.en-q8_0.bin"
        case .mediumQ5_0: "ggml-medium-q5_0.bin"
        case .mediumQ8_0: "ggml-medium-q8_0.bin"

        case .largeV2Q5_0: "ggml-large-v2-q5_0.bin"
        case .largeV2Q8_0: "ggml-large-v2-q8_0.bin"
        case .largeV3Q5_0: "ggml-large-v3-q5_0.bin"
        case .largeV3TurboQ5_0: "ggml-large-v3-turbo-q5_0.bin"
        case .largeV3TurboQ8_0: "ggml-large-v3-turbo-q8_0.bin"
        }
    }
}

public struct ModelStore {
    public static let shared = ModelStore()

    public let directory: URL

    /// Default repo: https://huggingface.co/ggerganov/whisper.cpp
    public var huggingFaceRepo: String = "ggerganov/whisper.cpp"

    public init(directory: URL? = nil) {
        if let directory { self.directory = directory; return }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.directory = appSupport
            .appendingPathComponent("WhisperCppKit", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    public func localURL(for model: WhisperModel) -> URL {
        directory.appendingPathComponent(model.filename)
    }

    public func remoteURL(for model: WhisperModel) -> URL {
        // “resolve/main/FILE” works for direct downloads.
        URL(string: "https://huggingface.co/\(huggingFaceRepo)/resolve/main/\(model.filename)?download=true")!
    }

    public func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func ensureDownloaded(
        _ model: WhisperModel,
        overwrite: Bool = false
    ) async throws -> URL {
        try await ensureDownloaded(model, remoteURL: remoteURL(for: model), overwrite: overwrite)
    }

    public func ensureDownloaded(
        _ model: WhisperModel,
        remoteURL: URL,
        overwrite: Bool = false
    ) async throws -> URL {

        try ensureDirectory()
        let dst = localURL(for: model)

        if FileManager.default.fileExists(atPath: dst.path) {
            if overwrite { try? FileManager.default.removeItem(at: dst) }
            else { return dst }
        }

        let (tmpURL, _) = try await URLSession.shared.download(from: remoteURL)

        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
        try fm.moveItem(at: tmpURL, to: dst)

        // Good default for iOS: do not back this up to iCloud
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = dst
        try mutable.setResourceValues(values)

        return dst
    }
}