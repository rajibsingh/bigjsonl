# Changelog

## [Unreleased]

### Added
- Swift Package with three targets: `BigJSONLCore`, `bigjsonl-cli`, `BigJSONLApp`.
- Lazy incremental `LineOffsetIndex` for byte-offset-based file navigation (core).
- Token and syntax highlighting model (`TokenType`, `Token`) in core.
- `SearchResult` and `LineInfo` model types in core.
- CLI tool with swift-argument-parser: `bigjsonl <file> [--line] [--search] [--no-color]`.
- SwiftUI app skeleton with `DocumentGroup` entry point.
- `BigJSONLDocument` with overridden read path (never loads full file into memory).
- `MappedFile` — memory-mapped file I/O via `mmap` + `DispatchData` for zero-copy windowed reads.
- `JSONTokenizer` — produces byte-accurate `[Token]` arrays from JSON lines using swift-json validation and raw UTF-8 scanning.
- `LineOffsetIndex.ensureLineIndexed(_:mappedFile:)` — lazy incremental line-to-byte-offset index building.
- `LineOffsetIndex.byteRangeForLine(_:fileSize:)` — returns the byte range for an indexed line.
- Test suite: 23 tests covering tokenization, mapped file I/O, and lazy index building against real test data.
- `docs/ARCHITECTURE.md` with full design documentation.
- `docs/PROJECT_VISION.md` with vision, principles, and settled design decisions.
- `AGENTS.md` with changelog-first development workflow.
- `CHANGELOG.md` with Keep a Changelog conventions.
- Test data directory `test-files/` with pi session log samples for local testing.

### Changed
- `.gitignore` ignores `test-files/`, `*.jsonl`, and `.swiftpm/` to prevent leaking sensitive chat data from test files.
