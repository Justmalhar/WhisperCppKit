import Foundation
import WhisperCpp

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public final class WhisperContext: @unchecked Sendable {
    private let ctx: OpaquePointer
    private let verbose: Bool

    // MARK: - stderr silencer (C-level logs)

    private enum StderrSilencer {
        static func withSilencedStderr<T>(_ body: () throws -> T) rethrows -> T {
            let stderrFD = STDERR_FILENO

            // Duplicate current stderr
            let saved = dup(stderrFD)
            if saved == -1 { return try body() }

            // Redirect stderr -> /dev/null
            let devnull = open("/dev/null", O_WRONLY)
            if devnull == -1 {
                close(saved)
                return try body()
            }

            fflush(stderr)
            _ = dup2(devnull, stderrFD)
            close(devnull)

            defer {
                fflush(stderr)
                _ = dup2(saved, stderrFD)
                close(saved)
            }

            return try body()
        }
    }

    private static func silenceIfNeeded<T>(verbose: Bool, _ body: () throws -> T) rethrows -> T {
        if verbose { return try body() }
        return try StderrSilencer.withSilencedStderr(body)
    }

    // MARK: - Init (non-deprecated)

    /// Default init (GPU on, flash-attn on, device 0).
    /// verbose=false silences whisper.cpp / ggml init logs.
    public convenience init(modelPath: String, verbose: Bool = false) throws {
        try self.init(modelPath: modelPath, useGPU: true, flashAttn: true, gpuDevice: 0, verbose: verbose)
    }

    /// Init using whisper.cpp params (avoids deprecated whisper_init_from_file).
    public init(
        modelPath: String,
        useGPU: Bool,
        flashAttn: Bool,
        gpuDevice: Int32,
        verbose: Bool = false
    ) throws {
        self.verbose = verbose

        var p = whisper_context_default_params()
        p.use_gpu = useGPU
        p.flash_attn = flashAttn
        p.gpu_device = gpuDevice

        let created: OpaquePointer? = try Self.silenceIfNeeded(verbose: verbose) {
            whisper_init_from_file_with_params(modelPath, p)
        }

        guard let c = created else {
            throw WhisperError.failedToInitContext(modelPath: modelPath)
        }
        self.ctx = c
    }

    deinit {
        // whisper_free can also print (e.g. ggml_metal_free)
        _ = try? Self.silenceIfNeeded(verbose: verbose) {
            whisper_free(ctx)
        }
    }

    // MARK: - Callback bridge

    private final class CallbackBox {
        let onProgress: (@Sendable (Int32) -> Void)?
        let onNewSegment: (@Sendable (WhisperSegment) -> Void)?

        var lastEmittedSegmentIndex: Int32 = -1
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

    private static let progressThunk: @convention(c) (OpaquePointer?, OpaquePointer?, Int32, UnsafeMutableRawPointer?) -> Void = {
        _, _, progress, userData in
        guard let userData else { return }
        let box = Unmanaged<CallbackBox>.fromOpaque(userData).takeUnretainedValue()
        box.onProgress?(progress)
    }

    private static let newSegmentThunk: @convention(c) (OpaquePointer?, OpaquePointer?, Int32, UnsafeMutableRawPointer?) -> Void = {
        _, _, nNew, userData in
        guard let userData else { return }
        let box = Unmanaged<CallbackBox>.fromOpaque(userData).takeUnretainedValue()
        guard let cb = box.onNewSegment, nNew > 0 else { return }

        let total = whisper_full_n_segments(box.ctx)
        if total <= 0 { return }

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

        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false

        params.translate = options.translateToEnglish
        params.n_threads = Int32(max(1, options.threads))

        let box: CallbackBox? = {
            if options.onProgress == nil && options.onNewSegment == nil { return nil }
            return CallbackBox(ctx: self.ctx, onProgress: options.onProgress, onNewSegment: options.onNewSegment)
        }()

        let unmanagedBox: Unmanaged<CallbackBox>?
        if let box {
            unmanagedBox = Unmanaged.passRetained(box)

            params.progress_callback = Self.progressThunk
            params.progress_callback_user_data = unmanagedBox!.toOpaque()

            params.new_segment_callback = Self.newSegmentThunk
            params.new_segment_callback_user_data = unmanagedBox!.toOpaque()
        } else {
            unmanagedBox = nil
        }

        defer { unmanagedBox?.release() }

        let code: Int32
        if let lang = options.language {
            code = lang.withCString { cstr in
                var p = params
                p.language = cstr
                return whisper_full(self.ctx, p, pcm16k, Int32(pcm16k.count))
            }
        } else {
            code = whisper_full(self.ctx, params, pcm16k, Int32(pcm16k.count))
        }

        guard code == 0 else { throw WhisperError.whisperFailed(code: code) }

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