# Repository: Sources
Generated: Tue Dec 16 10:53:48 IST 2025

## Directory Structure
```
total 8
drwxr-xr-x@  6 malharujawane  staff  192 Dec 16 10:53 .
drwxr-xr-x@ 18 malharujawane  staff  576 Dec 16 00:26 ..
-rw-r--r--@  1 malharujawane  staff   90 Dec 16 10:53 Sources_context.md
drwxr-xr-x@  8 malharujawane  staff  256 Dec 16 00:25 WhisperCppKit
drwxr-xr-x@  3 malharujawane  staff   96 Dec 16 00:25 WhisperCppKitCLI
drwxr-xr-x@  3 malharujawane  staff   96 Dec 15 20:08 WhisperSwift

/Users/malharujawane/Documents/Development/Projects/WhisperCppKit/Sources/WhisperCppKit:
total 64
drwxr-xr-x@ 8 malharujawane  staff   256 Dec 16 00:25 .
drwxr-xr-x@ 6 malharujawane  staff   192 Dec 16 10:53 ..
-rw-r--r--@ 1 malharujawane  staff  2897 Dec 16 00:45 AudioDecoder.swift
-rw-r--r--@ 1 malharujawane  staff  5357 Dec 16 00:19 ModelStore.swift
-rw-r--r--@ 1 malharujawane  staff   159 Dec 15 21:04 SmokeTest.swift
-rw-r--r--@ 1 malharujawane  staff  6219 Dec 16 10:32 WhisperContext.swift
-rw-r--r--@ 1 malharujawane  staff   802 Dec 16 01:07 WhisperTranscriber.swift
-rw-r--r--@ 1 malharujawane  staff  1592 Dec 16 01:07 WhisperTypes.swift

/Users/malharujawane/Documents/Development/Projects/WhisperCppKit/Sources/WhisperCppKitCLI:
total 40
drwxr-xr-x@ 3 malharujawane  staff     96 Dec 16 00:25 .
drwxr-xr-x@ 6 malharujawane  staff    192 Dec 16 10:53 ..
-rw-r--r--@ 1 malharujawane  staff  16411 Dec 16 00:50 main.swift

/Users/malharujawane/Documents/Development/Projects/WhisperCppKit/Sources/WhisperSwift:
total 8
drwxr-xr-x@ 3 malharujawane  staff   96 Dec 15 20:08 .
drwxr-xr-x@ 6 malharujawane  staff  192 Dec 16 10:53 ..
-rw-r--r--@ 1 malharujawane  staff  363 Dec 15 20:08 WhisperSwift.swift
```

## File Contents
================================================
FILE: WhisperCppKitCLI/main.swift
================================================
```swift
import Foundation
import WhisperCppKit

// MARK: - Progress UI

struct ProgressBar {
    let width: Int

    func render(downloaded: Int64, total: Int64) -> String {
        guard total > 0 else {
            return "[\(String(repeating: "░", count: width))]  --.--%  \(fmtMB(downloaded))/??"
        }

        let ratio = min(max(Double(downloaded) / Double(total), 0), 1)
        let filled = Int((Double(width) * ratio).rounded(.down))
        let empty = max(0, width - filled)

        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
        let pct = ratio * 100.0

        return "[\(bar)]  \(String(format: "%6.2f", pct))%  \(fmtMB(downloaded))/\(fmtMB(total))"
    }

    private func fmtMB(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024.0 * 1024.0)
        return String(format: "%.2fMB", mb)
    }
}

// MARK: - HuggingFace model IDs

enum WhisperModel: String, CaseIterable {
    // Stable IDs for the CLI
    case baseEn   = "base.en"
    case base     = "base"
    case tinyEn   = "tiny.en"
    case tiny     = "tiny"
    case smallEn  = "small.en"
    case small    = "small"
    case mediumEn = "medium.en"
    case medium   = "medium"
    case largeV1  = "large-v1"
    case largeV2  = "large-v2"
    case largeV3  = "large-v3"
    case largeV3Turbo = "large-v3-turbo"

    var filename: String {
        switch self {
        case .baseEn:   return "ggml-base.en.bin"
        case .base:     return "ggml-base.bin"
        case .tinyEn:   return "ggml-tiny.en.bin"
        case .tiny:     return "ggml-tiny.bin"
        case .smallEn:  return "ggml-small.en.bin"
        case .small:    return "ggml-small.bin"
        case .mediumEn: return "ggml-medium.en.bin"
        case .medium:   return "ggml-medium.bin"
        case .largeV1:  return "ggml-large-v1.bin"
        case .largeV2:  return "ggml-large-v2.bin"
        case .largeV3:  return "ggml-large-v3.bin"
        case .largeV3Turbo: return "ggml-large-v3-turbo.bin"
        }
    }
}

// MARK: - Model Store

struct ModelStore {
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
            return
        }

        // Default: Application Support/WhisperCppKit/Models
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.directory = appSupport
            .appendingPathComponent("WhisperCppKit", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func localURL(for model: WhisperModel) -> URL {
        directory.appendingPathComponent(model.filename)
    }

    func remoteURL(for model: WhisperModel) -> URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(model.filename)?download=true")!
    }

    func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try mutable.setResourceValues(values)
    }
}

// MARK: - Downloader with progress bar

final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let dst: URL
    private let overwrite: Bool
    private let onProgress: (Int64, Int64) -> Void
    private var continuation: CheckedContinuation<URL, Error>?

    init(dst: URL, overwrite: Bool, onProgress: @escaping (Int64, Int64) -> Void) {
        self.dst = dst
        self.overwrite = overwrite
        self.onProgress = onProgress
    }

    func download(from url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            self.continuation = cont

            let config = URLSessionConfiguration.default
            config.waitsForConnectivity = true
            config.requestCachePolicy = .reloadIgnoringLocalCacheData

            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)

            if fm.fileExists(atPath: dst.path) {
                if overwrite { try fm.removeItem(at: dst) }
                else {
                    continuation?.resume(returning: dst)
                    continuation = nil
                    session.invalidateAndCancel()
                    return
                }
            }

            try fm.moveItem(at: location, to: dst)

            continuation?.resume(returning: dst)
            continuation = nil
            session.invalidateAndCancel()
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
            session.invalidateAndCancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
            session.invalidateAndCancel()
        }
    }
}

// MARK: - CLI

@main
struct WhisperCppKitCLI {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    }

    static func normalizePath(_ p: String) -> String {
        let expanded = (p as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return expanded }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(expanded).path
    }

    static func usage() -> Never {
        let msg = """
        Usage:
          whispercppkit-cli models list
          whispercppkit-cli models path
          whispercppkit-cli models status
          whispercppkit-cli models pull <model-id> [--overwrite] [--models-dir <dir>]
          whispercppkit-cli models prune [--keep <id>]... [--dry-run] [--force] [--models-dir <dir>]

          whispercppkit-cli transcribe --model <model-id|path> --audio <path> [--lang en] [--threads 4] [--models-dir <dir>] [--overwrite-model]
          whispercppkit-cli --model <model-id|path> --audio <path> [--lang en] [--threads 4] [--models-dir <dir>] [--overwrite-model]

        Model IDs:
          \(WhisperModel.allCases.map(\.rawValue).joined(separator: ", "))

        Examples:
          whispercppkit-cli models path
          whispercppkit-cli models status
          whispercppkit-cli models pull base.en
          whispercppkit-cli --model base.en --audio "Tests/Samples/New Recording.m4a"
        """
        fputs(msg + "\n", stderr)
        exit(2)
    }

    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty else { usage() }

        func has(_ flag: String) -> Bool { args.contains(flag) }

        func values(after flag: String) -> [String] {
            var out: [String] = []
            var i = 0
            while i < args.count {
                if args[i] == flag, i + 1 < args.count {
                    out.append(args[i + 1])
                    i += 2
                } else {
                    i += 1
                }
            }
            return out
        }

        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }

        // models dir override
        var store = ModelStore()
        if let dir = value(after: "--models-dir") {
            store = ModelStore(directory: URL(fileURLWithPath: dir, isDirectory: true))
        }

        // Back-compat: if user passes flags directly, treat as `transcribe`
        let isFlagStyleTranscribe = args.first?.hasPrefix("-") == true || args.contains("--model") || args.contains("--audio")

        if args[0] == "models" {
            guard args.count >= 2 else { usage() }

            switch args[1] {
            case "list":
                for m in WhisperModel.allCases {
                    print("\(m.rawValue)\t->\t\(m.filename)")
                }
                return

            case "path":
                print(store.directory.path)
                return

            case "status":
                try store.ensureDirectory()
                try printStatus(store: store)
                return

            case "pull":
                guard args.count >= 3 else { usage() }
                let id = args[2]
                guard let model = WhisperModel(rawValue: id) else {
                    throw NSError(domain: "whispercppkit", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "Unknown model id: \(id)"])
                }

                let overwrite = has("--overwrite")
                let local = try await downloadWithProgress(store: store, model: model, overwrite: overwrite)
                print("Saved: \(local.path)")
                return

            case "prune":
                let dryRun = has("--dry-run") || !has("--force")
                let keepIDs = values(after: "--keep")
                let keepSet: Set<String> = Set(keepIDs.compactMap { WhisperModel(rawValue: $0)?.filename })

                try store.ensureDirectory()
                let fm = FileManager.default
                let files = (try? fm.contentsOfDirectory(at: store.directory, includingPropertiesForKeys: nil)) ?? []

                let candidates = files.filter { url in
                    let name = url.lastPathComponent
                    if keepSet.contains(name) { return false }
                    if name.hasSuffix(".partial") { return true } // cleanup partials too
                    return name.hasPrefix("ggml-") && (name.hasSuffix(".bin") || name.hasSuffix(".zip") || name.hasSuffix(".mlmodelc.zip"))
                }

                if candidates.isEmpty {
                    print("Nothing to prune in: \(store.directory.path)")
                    return
                }

                print("Models dir: \(store.directory.path)")
                print(dryRun ? "Dry-run (add --force to actually delete):" : "Deleting:")

                for url in candidates {
                    print("  - \(url.lastPathComponent)")
                    if !dryRun { try? fm.removeItem(at: url) }
                }
                return

            default:
                usage()
            }
        }

        if args[0] == "transcribe" || isFlagStyleTranscribe {
            let modelArgRaw = value(after: "--model")
            let audioArgRaw = value(after: "--audio")
            guard let modelArgRaw, let audioArgRaw else { usage() }

            let overwriteModel = has("--overwrite-model")

            // Normalize + resolve model
            let modelArgNormalized = normalizePath(modelArgRaw)
            let modelPath: String
            if FileManager.default.fileExists(atPath: modelArgNormalized) {
                modelPath = modelArgNormalized
            } else if let model = WhisperModel(rawValue: modelArgRaw) {
                let local = try await downloadWithProgress(store: store, model: model, overwrite: overwriteModel)
                modelPath = local.path
            } else {
                throw NSError(domain: "whispercppkit", code: 3,
                              userInfo: [NSLocalizedDescriptionKey:
                                "Model not found as path or id: \(modelArgRaw)\nTip: use a model id like 'base.en' OR a real file path."])
            }

            // Normalize + preflight audio
            let audioPath = normalizePath(audioArgRaw)
            guard FileManager.default.fileExists(atPath: audioPath) else {
                throw NSError(domain: "whispercppkit", code: 44,
                              userInfo: [NSLocalizedDescriptionKey:
                                "Audio file not found: \(audioPath)\nTip: don’t start with '/' unless it’s a real absolute path."])
            }

            var opts = WhisperOptions()
            opts.language = value(after: "--lang") ?? "en"
            opts.threads = Int(value(after: "--threads") ?? "4") ?? 4

            let segs = try WhisperTranscriber.transcribeFile(modelPath: modelPath, audioPath: audioPath, options: opts)
            for s in segs {
                print(String(format: "[%0.2f → %0.2f] %@", s.startTime, s.endTime, s.text))
            }
            return
        }

        usage()
    }

    // MARK: - Status

    static func printStatus(store: ModelStore) throws {
        let fm = FileManager.default

        var downloadedCount = 0
        var missingCount = 0
        var totalBytes: Int64 = 0

        print("Models dir: \(store.directory.path)\n")

        // nice column-ish output
        for m in WhisperModel.allCases {
            let url = store.localURL(for: m)
            if fm.fileExists(atPath: url.path) {
                downloadedCount += 1
                let sz = (try? fileSize(url)) ?? 0
                totalBytes += sz
                print("✅ \(m.rawValue)\t\(m.filename)\t(\(humanBytes(sz)))")
            } else {
                missingCount += 1
                print("⬜️ \(m.rawValue)\t\(m.filename)\t(missing)")
            }
        }

        // also show “unknown extra files” sitting in the dir
        let files = (try? fm.contentsOfDirectory(at: store.directory, includingPropertiesForKeys: nil)) ?? []
        let known = Set(WhisperModel.allCases.map { $0.filename })
        let extras = files
            .map(\.lastPathComponent)
            .filter { $0.hasPrefix("ggml-") && ( $0.hasSuffix(".bin") || $0.hasSuffix(".zip") || $0.hasSuffix(".mlmodelc.zip") || $0.hasSuffix(".partial") ) }
            .filter { !known.contains($0) }

        print("\nSummary:")
        print("  Downloaded: \(downloadedCount)")
        print("  Missing:    \(missingCount)")
        print("  Disk usage: \(humanBytes(totalBytes))")

        if !extras.isEmpty {
            print("\nExtras in models dir (not in CLI list):")
            for e in extras.sorted() {
                print("  • \(e)")
            }
        }
    }

    static func fileSize(_ url: URL) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func humanBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(bytes)
        var i = 0
        while v >= 1024, i < units.count - 1 {
            v /= 1024
            i += 1
        }
        return String(format: "%.2f %@", v, units[i])
    }

    // MARK: - Download with progress (sliding bar)

    static func downloadWithProgress(store: ModelStore, model: WhisperModel, overwrite: Bool) async throws -> URL {
        try store.ensureDirectory()

        let dst = store.localURL(for: model)
        let fm = FileManager.default

        if fm.fileExists(atPath: dst.path) {
            if overwrite { try? fm.removeItem(at: dst) }
            else { return dst }
        }

        let remote = store.remoteURL(for: model)

        let bar = ProgressBar(width: 34)
        let delegate = DownloadDelegate(dst: dst, overwrite: overwrite) { downloaded, total in
            let line = bar.render(downloaded: downloaded, total: total)
            fputs("\r\(line)", stdout)
            fflush(stdout)
        }

        print("Pulling \(model.rawValue) -> \(dst.path)")
        let local = try await delegate.download(from: remote)
        fputs("\n", stdout)

        try store.excludeFromBackup(local)
        return local
    }
}
```


================================================
FILE: WhisperSwift/WhisperSwift.swift
================================================
```swift
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

```


================================================
FILE: WhisperCppKit/SmokeTest.swift
================================================
```swift
import Foundation
import WhisperCpp

public enum WhisperCppKitSmokeTest {
    public static func ping() {
        _ = whisper_context_default_params()
    }
}

```


================================================
FILE: WhisperCppKit/ModelStore.swift
================================================
```swift
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
```


================================================
FILE: WhisperCppKit/WhisperTranscriber.swift
================================================
```swift
import Foundation

public enum WhisperTranscriber {
    public static func transcribeFile(
        modelPath: String,
        audioPath: String,
        options: WhisperOptions = .init()
    ) throws -> [WhisperSegment] {
        let ctx = try WhisperContext(modelPath: modelPath)
        let pcm = try AudioDecoder.decodeToPCM16k(url: URL(fileURLWithPath: audioPath))
        return try ctx.transcribe(pcm16k: pcm, options: options)
    }

    public static func transcribeURL(
        modelPath: String,
        audioURL: URL,
        options: WhisperOptions = .init()
    ) throws -> [WhisperSegment] {
        let ctx = try WhisperContext(modelPath: modelPath)
        let pcm = try AudioDecoder.decodeToPCM16k(url: audioURL)
        return try ctx.transcribe(pcm16k: pcm, options: options)
    }
}
```


================================================
FILE: WhisperCppKit/WhisperTypes.swift
================================================
```swift
import Foundation

public struct WhisperSegment: Sendable, Equatable {
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
```


================================================
FILE: WhisperCppKit/AudioDecoder.swift
================================================
```swift
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
```


================================================
FILE: WhisperCppKit/WhisperContext.swift
================================================
```swift
import Foundation
import WhisperCpp

public final class WhisperContext: @unchecked Sendable {
    private let ctx: OpaquePointer

    // MARK: - Init (non-deprecated)

    /// Default init (GPU on, flash-attn on, device 0, dtw off)
    public convenience init(modelPath: String) throws {
        try self.init(modelPath: modelPath, useGPU: true, flashAttn: true, gpuDevice: 0, dtw: false)
    }

    /// Init using whisper.cpp params (avoids deprecated whisper_init_from_file).
    public init(
        modelPath: String,
        useGPU: Bool,
        flashAttn: Bool,
        gpuDevice: Int32,
        dtw: Bool
    ) throws {
        var p = whisper_context_default_params()
        p.use_gpu = useGPU
        p.flash_attn = flashAttn
        p.gpu_device = gpuDevice
        p.dtw = dtw

        guard let c = whisper_init_from_file_with_params(modelPath, p) else {
            throw WhisperError.failedToInitContext(modelPath: modelPath)
        }
        self.ctx = c
    }

    deinit {
        whisper_free(ctx)
    }

    // MARK: - Callback bridge

    private final class CallbackBox {
        let onProgress: (@Sendable (Int32) -> Void)?
        let onNewSegment: (@Sendable (WhisperSegment) -> Void)?

        // used to avoid re-sending old segments when callback is called repeatedly
        var lastEmittedSegmentIndex: Int32 = -1

        // weak-ish reference is fine because box lifetime is scoped to transcribe()
        let ctx: OpaquePointer

        init(
            ctx: OpaquePointer,
            onProgress: (@Sendable (Int32) -> Void)?,
            onNewSegment: (@Sendable (WhisperSegment) -> Void)?
        ) {
            self.ctx = ctx
            self.onProgress = onProgress
            self.onNewSegment = onNewSegment
        }
    }

    // whisper.cpp: void (*progress_callback)(struct whisper_context * ctx, struct whisper_state * state, int progress, void * user_data);
    private static let progressThunk: @convention(c) (OpaquePointer?, OpaquePointer?, Int32, UnsafeMutableRawPointer?) -> Void = {
        _, _, progress, userData in
        guard let userData else { return }
        let box = Unmanaged<CallbackBox>.fromOpaque(userData).takeUnretainedValue()
        box.onProgress?(progress)
    }

    // whisper.cpp: void (*new_segment_callback)(struct whisper_context * ctx, struct whisper_state * state, int n_new, void * user_data);
    private static let newSegmentThunk: @convention(c) (OpaquePointer?, OpaquePointer?, Int32, UnsafeMutableRawPointer?) -> Void = {
        _, _, nNew, userData in
        guard let userData else { return }
        let box = Unmanaged<CallbackBox>.fromOpaque(userData).takeUnretainedValue()
        guard let cb = box.onNewSegment, nNew > 0 else { return }

        // Total segments so far
        let total = whisper_full_n_segments(box.ctx)
        if total <= 0 { return }

        // Emit only the newly added segments.
        // In whisper.cpp, new_segment callback is called with n_new (count of new segs)
        // but we also guard with lastEmittedSegmentIndex for safety.
        let start = max(Int32(0), total - nNew)

        for i in start..<total {
            if i <= box.lastEmittedSegmentIndex { continue }

            let t0 = Double(whisper_full_get_segment_t0(box.ctx, i)) * 0.01
            let t1 = Double(whisper_full_get_segment_t1(box.ctx, i)) * 0.01
            let cstr = whisper_full_get_segment_text(box.ctx, i)
            let text = cstr.map { String(cString: $0) } ?? ""

            cb(.init(index: Int(i), startTime: t0, endTime: t1, text: text))
            box.lastEmittedSegmentIndex = i
        }
    }

    /// Transcribe mono 16kHz PCM float samples in [-1, 1]
    public func transcribe(pcm16k: [Float], options: WhisperOptions = .init()) throws -> [WhisperSegment] {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)

        // make it quiet
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false

        params.translate = options.translateToEnglish
        params.n_threads = Int32(max(1, options.threads))

        // Wire callbacks if requested
        let box: CallbackBox? = {
            if options.onProgress == nil && options.onNewSegment == nil { return nil }
            return CallbackBox(ctx: self.ctx, onProgress: options.onProgress, onNewSegment: options.onNewSegment)
        }()

        let unmanagedBox: Unmanaged<CallbackBox>?
        if let box {
            unmanagedBox = Unmanaged.passRetained(box)

            // Attach callbacks + user data
            params.progress_callback = Self.progressThunk
            params.progress_callback_user_data = unmanagedBox!.toOpaque()

            params.new_segment_callback = Self.newSegmentThunk
            params.new_segment_callback_user_data = unmanagedBox!.toOpaque()
        } else {
            unmanagedBox = nil
        }

        defer {
            // IMPORTANT: balance passRetained
            if let unmanagedBox {
                unmanagedBox.release()
            }
        }

        let run: () -> Int32 = {
            whisper_full(self.ctx, params, pcm16k, Int32(pcm16k.count))
        }

        let code: Int32
        if let lang = options.language {
            code = lang.withCString { cstr in
                var p = params
                p.language = cstr
                return whisper_full(self.ctx, p, pcm16k, Int32(pcm16k.count))
            }
        } else {
            code = run()
        }

        guard code == 0 else { throw WhisperError.whisperFailed(code: code) }

        // Build final segments list
        let n = Int(whisper_full_n_segments(ctx))
        var out: [WhisperSegment] = []
        out.reserveCapacity(n)

        for i in 0..<n {
            let t0 = Double(whisper_full_get_segment_t0(ctx, Int32(i))) * 0.01
            let t1 = Double(whisper_full_get_segment_t1(ctx, Int32(i))) * 0.01
            let cstr = whisper_full_get_segment_text(ctx, Int32(i))
            let text = cstr.map { String(cString: $0) } ?? ""
            out.append(.init(index: i, startTime: t0, endTime: t1, text: text))
        }

        return out
    }
}
```


