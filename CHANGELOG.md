# Changelog

## [Unreleased]

## [0.1.0] — 2026-06-15

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
- Test suite: 30 tests covering tokenization, mapped file I/O, lazy index building, search, and app viewport behavior.
- `docs/ARCHITECTURE.md` with full design documentation.
- `docs/PROJECT_VISION.md` with vision, principles, and settled design decisions.
- `AGENTS.md` with changelog-first development workflow.
- `CHANGELOG.md` with Keep a Changelog conventions.
- Test data directory `test-files/` with pi session log samples for local testing.
- SwiftUI app (executable product `BigJSONLApp`) with welcome screen, file importer, scrollable syntax-highlighted line list, line inspector sidebar, and toolbar search.
- `DocumentViewModel` (`@Observable`) — bridges core library to SwiftUI views, manages viewport and search state.
- `LineView` — renders a single JSONL line with color-coded syntax highlighting via `Text` + `foregroundColor`.
- `LineInspectorView` — shows byte offset, length, and JSON validity for a selected line.

### Changed
- Speed up content-heavy inspector selections by formatting and tokenizing off the main actor, caching recent results, and rendering through AppKit.
- Left-side line rows now use plain text, reserving JSON syntax highlighting for the inspector Content pane.
- Line rows now truncate after three visual lines, while the full-height inspector pretty-prints and syntax-highlights JSON content.
- `.gitignore` ignores `test-files/`, `*.jsonl`, and `.swiftpm/` to prevent leaking sensitive chat data from test files.
- `LineOffsetIndex.ensureLineIndexed` now uses batch `Data(chunk)` + `[UInt8]` byte scanning for 5x faster full-file scans.

### Fixed
- Line selection becoming stuck after the first click because selectable row text intercepted subsequent mouse gestures.
- SwiftUI app startup failures caused by missing executable bundle metadata and viewport edge loaders mutating line state during initial layout.
- Hardened large-file navigation, bounded cancellable search, mapped-data lifetimes, empty-file handling, CLI validation, and deterministic test coverage to address the 2026-06-15 code review.
- `.jsonl` files grayed out in file open dialog — switched `UTType` from `importedAs:` to `UTType(tag:conformingTo:)` for proper system recognition.
- Hidden files (dotfiles) not visible in file open dialog — replaced SwiftUI `fileImporter` with custom `NSOpenPanel` with `showsHiddenFiles = true`.
- Files still grayed out with content type filter — removed `allowedContentTypes` filter entirely; validates extension after selection.
- `BigJSONLApp` target not showing as runnable in Xcode — changed from `.target` to `.executableTarget` and added to `products`.
- `Searcher` subprocess deadlock on large output — reads stdout on background dispatch queue while process runs.

[0.1.0]: https://github.com/rajibsingh/bigjsonl/releases/tag/v0.1.0
