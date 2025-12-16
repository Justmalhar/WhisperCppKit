# Changelog

All notable changes to **WhisperCppKit** will be documented in this file.

This project follows **Semantic Versioning** (https://semver.org).

## v0.1.0 — 2025-12-16

Initial public release.

### Added
- Swift Package (`WhisperCppKit`) targeting **macOS 13+** and **iOS 14+**.
- Bundled `WhisperCpp.xcframework` as a SwiftPM **binary target**.
- `WhisperCppKit` wrapper API for file transcription via `WhisperTranscriber.transcribeFile(...)`.
- CLI tool: `whispercppkit-cli`
  - Model management: `models list|path|status|pull|prune`
  - Transcription modes: plain, JSON, streaming NDJSON
  - Progress rendering to stderr (pipe-friendly stdout)
  - `--translate`, `--threads`, `--lang`, `--verbose`

### Notes
- Whisper model weights are downloaded at runtime by the CLI from the official `ggerganov/whisper.cpp` HuggingFace repo.
- See `README.md` for installation and usage examples.
