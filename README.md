# WhisperCppKit

Swift-first wrapper around **whisper.cpp** for **macOS** and **iOS**, packaged as a SwiftPM library with a companion CLI.

- ✅ **Swift Package Manager** (library + CLI)
- ✅ **macOS (13+)** + **iOS (14+)**
- ✅ Uses a prebuilt `WhisperCpp.xcframework` (binary target) for fast setup
- ✅ CLI supports plain text, JSON, **NDJSON streaming**, and progress on **stderr**

> This repo ships two libraries:
>
> - **`WhisperCppKit`** — the Swift API you’ll use in apps
> - **`WhisperCpp`** — the prebuilt `xcframework` wrapper around whisper.cpp (binary target)

---

## Contents

- [Install](#install)
  - [SwiftPM](#swiftpm)
  - [CLI install (local)](#cli-install-local)
- [Quick start](#quick-start)
  - [Library](#library)
  - [CLI](#cli)
- [CLI reference](#cli-reference)
  - [Transcribe](#transcribe)
  - [Models](#models)
  - [Stdout vs stderr](#stdout-vs-stderr)
- [Notes](#notes)
  - [Model storage path](#model-storage-path)
  - [Performance](#performance)
  - [iOS usage](#ios-usage)
- [Development](#development)
  - [Build &amp; test](#build--test)
  - [Repo layout](#repo-layout)
- [License &amp; attribution](#license--attribution)

---

## Install

### SwiftPM

Add this package to your app (Xcode: **File → Add Packages…**) and paste this repo URL:

```
https://github.com/Justmalhar/WhisperCppKit
```

Then import:

```swift
import WhisperCppKit
```

Your project will link against:

- `WhisperCppKit` (Swift wrapper)
- `WhisperCpp` (`Frameworks/WhisperCpp.xcframework`)
- `libc++` and `Accelerate` (configured in `Package.swift`)

---

### CLI install (local)

SwiftPM doesn’t “install” executables globally by default, so build and copy the binary:

```bash
swift build -c release
install -m 755 .build/release/whispercppkit-cli /usr/local/bin/whispercppkit-cli
```

Verify:

```bash
whispercppkit-cli --help
```

> Tip: during development you can run the debug binary directly:
> `./.build/debug/whispercppkit-cli --help`

---

## Quick start

### Library

Minimal usage (transcribe a file and return segments):

```swift
import WhisperCppKit

var opts = WhisperOptions()
opts.language = "en"
opts.threads = 4
opts.translateToEnglish = false
opts.verbose = false

let segments = try WhisperTranscriber.transcribeFile(
    modelPath: "/path/to/ggml-base.en.bin",
    audioPath: "/path/to/audio.m4a",
    options: opts
)

for s in segments {
    print(String(format: "[%0.2f → %0.2f] %@", s.startTime, s.endTime, s.text))
}
```

Streaming segments as they are produced:

```swift
import WhisperCppKit

var opts = WhisperOptions()
opts.language = "en"
opts.threads = 4

opts.onNewSegment = { seg in
    print(String(format: "[%0.2f → %0.2f] %@", seg.startTime, seg.endTime, seg.text))
}

_ = try WhisperTranscriber.transcribeFile(
    modelPath: "/path/to/ggml-base.en.bin",
    audioPath: "/path/to/audio.m4a",
    options: opts
)
```

---

### CLI

Examples using the included sample file (adjust paths as needed):

```bash
# plain output
whispercppkit-cli --model base.en --audio "Tests/Samples/New Recording.m4a"

# streaming + progress (progress prints to stderr)
whispercppkit-cli --model base.en --audio "Tests/Samples/New Recording.m4a" --stream --progress

# JSON (single object)
whispercppkit-cli --model base.en --audio "Tests/Samples/New Recording.m4a" --json

# NDJSON streaming (one JSON object per segment line)
whispercppkit-cli --model base.en --audio "Tests/Samples/New Recording.m4a" --stream --json

# translate to English
whispercppkit-cli --model base.en --audio "Tests/Samples/New Recording.m4a" --translate
```

---

## CLI reference

### Transcribe

You can call the CLI in two equivalent ways:

```bash
whispercppkit-cli transcribe --model <model-id|path> --audio <path> [opts...]
whispercppkit-cli --model <model-id|path> --audio <path> [opts...]
```

Options:

- `--lang <code>` (default: `en`)
- `--threads <n>` (default: `4`)
- `--translate` (translate → English)
- `--stream` (print segments as they are produced)
- `--no-stream` (force non-streaming)
- `--json` (emit JSON; with `--stream` emits NDJSON)
- `--progress` (show progress percent on **stderr**)
- `--verbose` (forward whisper.cpp logs to **stderr**)

---

### Models

The CLI has a simple model store and can download ggml models automatically when you pass a known model id.

List supported IDs:

```bash
whispercppkit-cli models list
```

Show models directory path:

```bash
whispercppkit-cli models path
```

Show local cache status:

```bash
whispercppkit-cli models status
```

Download a model:

```bash
whispercppkit-cli models pull base.en
```

Prune unused / partial / extra files:

```bash
# dry-run by default (or explicitly)
whispercppkit-cli models prune --dry-run

# actually delete
whispercppkit-cli models prune --force

# keep one or more model IDs
whispercppkit-cli models prune --keep base.en --keep small.en --force
```

Override model directory:

```bash
whispercppkit-cli models status --models-dir "/path/to/models"
```

---

### Stdout vs stderr

The CLI is designed to be pipe-friendly:

- **stdout**:
  - segment text output (`--stream` or default)
  - JSON output (`--json`)
  - NDJSON segment stream (`--stream --json`)
- **stderr**:
  - progress line (`--progress`)
  - whisper.cpp logs (`--verbose`)
  - errors and warnings

Examples:

Pretty-print JSON while capturing progress/logs:

```bash
whispercppkit-cli --model base.en --audio "file.m4a" --json --progress 2>/tmp/stderr.log | python3 -m json.tool
```

Validate NDJSON stream:

```bash
whispercppkit-cli --model base.en --audio "file.m4a" --stream --json --progress 2>/tmp/stderr.log \
  | python3 -c 'import sys,json; [json.loads(l) for l in sys.stdin if l.strip()]; print("NDJSON OK")'
```

Capture output cleanly:

```bash
whispercppkit-cli --model base.en --audio "file.m4a" --stream --progress 1>/tmp/out.txt 2>/tmp/err.txt
cat /tmp/out.txt
cat /tmp/err.txt
```

---

## Notes

### Model storage path

By default, models are stored in:

- **macOS**: `~/Library/Application Support/WhisperCppKit/Models`

The CLI will download models into that directory when you pass a known model id like `base.en`.
You can also pass a direct model file path to `--model`.

---

### Performance

- On Apple Silicon, the underlying whisper.cpp build can use **Metal** (when compiled that way in the bundled framework).
- You can tune:
  - `--threads` for CPU-side scheduling
  - model choice (`tiny` / `base` / `small` / `medium` / `large*`)
  - optional translation (`--translate`)

---

### iOS usage

The package supports iOS 14+, but note:

- iOS sandboxing means your model file must be stored in your app container (Documents/Library/tmp/etc).
- For app distribution, you’ll want a plan for model delivery (on-device download, bundled asset, etc).

---

## Development

### Build & test

```bash
swift build
swift test
```

Run the CLI (debug):

```bash
swift run whispercppkit-cli --help
swift run whispercppkit-cli --model base.en --audio "Tests/Samples/New Recording.m4a" --stream --progress
```

Or run the built binary:

```bash
swift build
./.build/debug/whispercppkit-cli --help
```

---

### Repo layout

- `Sources/WhisperCppKit/` — Swift wrapper (public API)
- `Sources/WhisperCppKitCLI/` — CLI executable target
- `Frameworks/WhisperCpp.xcframework/` — binary target providing whisper.cpp bindings
- `Tests/WhisperCppKitTests/` — unit tests / smoke tests

---

## License

Licenced under [MIT](LICENSE)

- Your Swift wrapper code is licensed under the LICENSE file in this repo.
- **whisper.cpp** is a separate upstream project; make sure you comply with its license and include proper attribution when distributing binaries.
- The bundled `WhisperCpp.xcframework` contains compiled components; if you rebuild it, ensure you preserve license notices and attributions.

---

## Roadmap (near-term)

- ✅ SwiftPM library + CLI
- ✅ Clean stdout/stderr separation for piping
- ⏭ CI workflow (macOS build + tests)
- ⏭ Prebuilt release artifacts (GitHub Releases)
- ⏭ macOS app (Superwhisper-style) built on top of `WhisperCppKit`

## Support Development

To support development for this project you can donate on: [https://ko-fi.com/justmalhar](https://ko-fi.com/justmalhar)

## Connect with Me

- **Twitter/X**: [@justmalhar](https://twitter.com/justmalhar) 🛠
- **LinkedIn**: [Malhar Ujawane](https://linkedin.com/in/justmalhar) 💻
- **GitHub**: [justmalhar](https://github.com/justmalhar) 💻
