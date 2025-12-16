# Changelog

All notable changes to **WhisperCppKit** will be documented in this file.

This project follows **Semantic Versioning** (https://semver.org).

## [0.1.1] - 2025-12-16

### Added

- SwiftPM library targets: `WhisperCppKit` (Swift wrapper) and `WhisperCpp` (binary `xcframework`).
- CLI executable: `whispercppkit-cli` with:
  - model management (`models list|path|status|pull|prune`)
  - transcription (`--model`, `--audio`, `--lang`, `--threads`, `--translate`)
  - streaming output (`--stream`)
  - JSON output (`--json`, NDJSON when combined with `--stream`)
  - progress output on stderr (`--progress`)
- GitHub Actions CI workflow for macOS (build + tests).

### Changed

- Improved CLI TTY output: when using `--stream --progress`, the progress line no longer glues into the first streamed segment (prints a newline before the first streamed segment, once).
- CI/build linking updated for Metal-backed builds (adds `Metal` framework linkage) to avoid undefined symbol errors from ggml-metal objects on newer Xcode toolchains.

### Fixed

- CI linker failure on macOS runners with newer Xcode: missing `MTLResidencySetDescriptor` symbol is resolved by linking `Metal`.

## v0.1.0 — 2025-12-16

Initial public release.

### Added

- Swift Package (`WhisperCppKit`) targeting **macOS 13+** and **iOS 14+**.
- Bundled `WhisperCpp.xcframework` as a SwiftPM **binary target**.
- `WhisperCppKit` wrapper API for file transcription via `WhisperTranscriber.transcribeFile(...)`.CLI tool: `whispercppkit-cli`
- - Model management: `models list|path|status|pull|prune`
  - Transcription modes: plain, JSON, streaming NDJSON
  - Progress rendering to stderr (pipe-friendly stdout)
  - `--translate`, `--threads`, `--lang`, `--verbose`

### Notes

- Whisper model weights are downloaded at runtime by the CLI from the official `ggerganov/whisper.cpp` HuggingFace repo.
- See `README.md` for installation and usage examples.
