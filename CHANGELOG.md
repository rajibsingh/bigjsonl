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
- `Searcher` — auto-detects ripgrep/grep, runs subprocess with pipe deadlock handling, parses results into `[SearchResult]`.
- `ANSIRenderer` — ANSI syntax highlighting with line-number gutter for the CLI.
- CLI now renders syntax-highlighted JSON lines using `MappedFile`, `LineOffsetIndex`, and `JSONTokenizer`.
- CLI `--search` flag runs grep/rg and jumps to the first match.
- CLI `--line` flag jumps to a specific line.
- CLI `--window-lines` flag controls viewport height.
- Test suite: 24 tests covering tokenization, mapped file I/O, lazy index building, and search.
- `docs/ARCHITECTURE.md` with full design documentation.
- `docs/PROJECT_VISION.md` with vision, principles, and settled design decisions.
- `AGENTS.md` with changelog-first development workflow.
- `CHANGELOG.md` with Keep a Changelog conventions.
- Test data directory `test-files/` with pi session log samples for local testing.
- SwiftUI app with welcome screen, file importer, scrollable syntax-highlighted line list, line inspector sidebar, and toolbar search.
- `DocumentViewModel` (`@Observable`) — bridges core library to SwiftUI views, manages viewport and search state.
- `LineView` — renders a single JSONL line with color-coded syntax highlighting via `Text` + `foregroundColor`.
- `LineInspectorView` — shows byte offset, length, and JSON validity for a selected line.

### Changed
- `.gitignore` ignores `test-files/`, `*.jsonl`, and `.swiftpm/` to prevent leaking sensitive chat data from test files.
- `LineOffsetIndex.ensureLineIndexed` now uses batch `Data(chunk)` + `[UInt8]` byte scanning for 5x faster full-file scans.
