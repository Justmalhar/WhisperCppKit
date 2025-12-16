import Foundation
import WhisperCppKit


// MARK: - Clean progress (stderr, single-line)

final class CLIProgress: @unchecked Sendable {
    private let enabled: Bool
    private let lock = NSLock()
    private var last: Int32 = -1
    private var didPrint = false

    init(enabled: Bool) { self.enabled = enabled }

    func update(_ p: Int32) {
        guard enabled else { return }

        lock.lock()
        defer { lock.unlock() }

        // clamp + de-dupe
        let pp = max(0, min(100, p))
        guard pp != last else { return }
        last = pp
        didPrint = true

        // one-line overwrite to stderr
        let line = String(format: "\rTranscribing: %3d%%", Int(pp))
        fputs(line, stderr)
        fflush(stderr)
    }

    // Print a newline once, if we've printed any progress on the current line.
    // Call this right before writing streamed output to stdout.
    func breakLineIfNeeded() {
        guard enabled else { return }

        lock.lock()
        defer { lock.unlock() }

        guard didPrint else { return }
        fputs("\n", stderr)
        fflush(stderr)
        didPrint = false
    }

    func finish() {
        guard enabled else { return }

        lock.lock()
        defer { lock.unlock() }

        // ensure we end at 100% exactly once
        if last < 100 {
            let line = String(format: "\rTranscribing: %3d%%", 100)
            fputs(line, stderr)
        }
        if didPrint {
            fputs("\n", stderr)
            fflush(stderr)
        }
    }
}

// MARK: - Progress UI (download)

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

// MARK: - HuggingFace model IDs (CLI)

enum WhisperModel: String, CaseIterable {
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

// MARK: - Model Store (CLI)

struct ModelStore {
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
            return
        }

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

// MARK: - Downloader (with progress)

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

// MARK: - JSON output models

private struct TranscriptionResult: Codable {
    let model: String
    let audio: String
    let language: String?
    let translateToEnglish: Bool
    let threads: Int
    let segments: [WhisperSegment]
}

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

          whispercppkit-cli transcribe --model <model-id|path> --audio <path> [opts...]
          whispercppkit-cli --model <model-id|path> --audio <path> [opts...]

        Transcribe opts:
          --lang <code>        (default: en)
          --threads <n>        (default: 4)
          --translate          (translate -> English)
          --stream             (print segments as they are produced)
          --no-stream          (force non-streaming)
          --json               (emit JSON; with --stream emits NDJSON)
          --progress           (show progress % on stderr)
          --verbose            (show whisper.cpp logs on stderr)

        Model IDs:
          \(WhisperModel.allCases.map(\.rawValue).joined(separator: ", "))

        Examples:
          whispercppkit-cli models status
          whispercppkit-cli models pull base.en
          whispercppkit-cli --model base.en --audio "Tests/Samples/New Recording.m4a"
          whispercppkit-cli --model base.en --audio "Tests/Samples/New Recording.m4a" --stream --progress
          whispercppkit-cli --model base.en --audio "Tests/Samples/New Recording.m4a" --json
          whispercppkit-cli --model base.en --audio "Tests/Samples/New Recording.m4a" --stream --json   # NDJSON
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
                    if name.hasSuffix(".partial") { return true }
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

            // flags
            let json = has("--json")
            let stream = has("--stream") && !has("--no-stream")
            let showProgress = has("--progress")
            let translate = has("--translate")

            // Normalize + resolve model
            let modelArgNormalized = normalizePath(modelArgRaw)
            let modelPath: String
            let modelIDForOutput: String

            if FileManager.default.fileExists(atPath: modelArgNormalized) {
                modelPath = modelArgNormalized
                modelIDForOutput = modelArgRaw
            } else if let model = WhisperModel(rawValue: modelArgRaw) {
                let local = try await downloadWithProgress(store: store, model: model, overwrite: overwriteModel)
                modelPath = local.path
                modelIDForOutput = model.rawValue
            } else {
                throw NSError(
                    domain: "whispercppkit",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Model not found as path or id: \(modelArgRaw)\nTip: use a model id like 'base.en' OR a real file path."]
                )
            }

            // Normalize + preflight audio
            let audioPath = normalizePath(audioArgRaw)
            guard FileManager.default.fileExists(atPath: audioPath) else {
                throw NSError(
                    domain: "whispercppkit",
                    code: 44,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Audio file not found: \(audioPath)\nTip: don’t start with '/' unless it’s a real absolute path."]
                )
            }

            // Options
            var opts = WhisperOptions()
            opts.language = value(after: "--lang") ?? "en"
            opts.threads = Int(value(after: "--threads") ?? "4") ?? 4
            opts.translateToEnglish = translate
            opts.verbose = has("--verbose")

            let progressUI = CLIProgress(enabled: showProgress)
            defer { progressUI.finish() }

            if showProgress {
                opts.onProgress = { p in
                    progressUI.update(p)
                }
            }

            // Streaming callback
            if stream {
                if json {
                    // NDJSON: one JSON object per line
                    opts.onNewSegment = { seg in
                        progressUI.breakLineIfNeeded()
                        do {
                            let enc = JSONEncoder()
                            enc.outputFormatting = []
                            let data = try enc.encode(seg)
                            if let s = String(data: data, encoding: .utf8) {
                                fputs(s + "\n", stderr)
                                fflush(stderr)
                            }
                        } catch {
                            fputs("⚠️ JSON encode failed for segment \(seg.index): \(error)\n", stderr)
                            fflush(stderr)
                        }
                    }
                } else {
                    opts.onNewSegment = { seg in
                        progressUI.breakLineIfNeeded()
                        print(String(format: "[%0.2f → %0.2f] %@", seg.startTime, seg.endTime, seg.text))
                        fflush(stdout)
                    }
                }
            }

            // ✅ IMPORTANT: use public API; CLI must not touch AudioDecoder directly
            let finalSegs = try WhisperTranscriber.transcribeFile(
                modelPath: modelPath,
                audioPath: audioPath,
                options: opts
            )

            // Output modes:
            // - stream: already printed via callbacks (NDJSON or plain)
            // - json (no stream): print full JSON object
            // - default: print plain segments
            if !stream {
                if json {
                    let res = TranscriptionResult(
                        model: modelIDForOutput,
                        audio: audioPath,
                        language: opts.language,
                        translateToEnglish: opts.translateToEnglish,
                        threads: opts.threads,
                        segments: finalSegs
                    )
                    let enc = JSONEncoder()
                    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try enc.encode(res)
                    if let s = String(data: data, encoding: .utf8) {
                        print(s)
                    }
                } else {
                    for s in finalSegs {
                        print(String(format: "[%0.2f → %0.2f] %@", s.startTime, s.endTime, s.text))
                    }
                }
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

        let files = (try? fm.contentsOfDirectory(at: store.directory, includingPropertiesForKeys: nil)) ?? []
        let known = Set(WhisperModel.allCases.map { $0.filename })
        let extras = files
            .map(\.lastPathComponent)
            .filter { $0.hasPrefix("ggml-") && ($0.hasSuffix(".bin") || $0.hasSuffix(".zip") || $0.hasSuffix(".mlmodelc.zip") || $0.hasSuffix(".partial")) }
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
            fputs("\r\(line)", stderr)
            fflush(stderr)
        }

        print("Pulling \(model.rawValue) -> \(dst.path)")
        let local = try await delegate.download(from: remote)
        fputs("\n", stderr)

        try store.excludeFromBackup(local)
        return local
    }
}