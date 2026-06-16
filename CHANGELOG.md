# Changelog

## [Unreleased]

### Added
- Manual reload (⌘R / toolbar button) — re-opens the current file from scratch, picking up any new content written since the file was opened. Search is cleared on reload. The button is disabled when no file is open.
- Tabbed interface — multiple JSONL files can be open simultaneously in a single window. Each tab is fully independent (its own viewport, index, search state, and inspector). A + button opens a new empty tab showing the welcome screen; ⌘T is the keyboard shortcut. Closing the last tab resets it to empty rather than quitting.
- `TabItem` — model owning a tab's URL, `BigJSONLDocument`, `DocumentViewModel`, and display title.
- `TabBarView` — horizontal tab strip with per-tab close buttons, scrollable when many tabs are open, and a + button at the right end.
- Multi-file open — the file dialog now allows multiple selection; each chosen file opens in its own tab. The first file reuses the current tab if it is empty; subsequent files create new tabs. Focus lands on the last opened tab.
- Search results pane in the left column — when a search returns matches, the line list is replaced by a scrollable list of results showing line number and snippet with the matched term highlighted in orange. Clicking any result jumps the viewport to that line without dismissing the results, so the user can navigate freely between matches. A × button in the toolbar clears the search and restores the line list.
- `clearSearch()` on `DocumentViewModel` — resets query, results, and error state in one call.
- Inspector auto-selects line 1 on file open so the content pane is never empty.
- `\n` escape sequences inside JSON string values are expanded into a visible `\n` marker followed by a real line break in both the line list and the inspector content pane, improving readability of content-heavy records.

### Changed
- Parallelize per-line viewport preparation (mmap read, UTF-8 decode, JSON validity check) across a `TaskGroup` instead of a single serial loop, speeding up window loads on multi-core Macs while preserving line order.
- Smooth main-pane scrolling with an overscanned moving viewport that preloads buffered rows before and after the visible line list while keeping existing rows rendered during background loads.
- Reduce retained memory for content-heavy files by storing bounded line-list previews and loading full selected-line text only for the inspector.
- Improve responsiveness and memory efficiency by preparing viewports off the main actor, bounding retained search snippets, scanning mmap bytes directly, cancelling stale inspector work, and disposing tab resources on close/reload.

### Fixed
- Coalesce repeated main-pane edge scroll events so one momentum gesture does not load several viewport windows in sequence.
- Keep the selected line's inspector visible when main-pane scrolling moves that line out of the loaded viewport.
- Re-prepare inspector content after tab switches so selected loaded rows do not show "Content unavailable."
- Prevent extra scrolling at EOF from jumping the line list back toward the beginning of the file.
- Grow the loaded line viewport from the left-pane height so resizing tall windows fills the pane instead of showing a misleading blank area.
- Clarify active tab styling in dark mode with stronger fill, border, and accent underline.
- Search query disappearing while typing and not persisting across tab switches — moved `searchQuery` state and the search toolbar out of `ContentView` into `BigJSONLApp` so the text field is never torn down on re-render or tab switch.
- File open doing nothing — `selectedTabID` was initialised to a different `UUID` than `tabs[0].id`, so `selectedTab` was always `nil`; fixed by creating the first `TabItem` and capturing its `id` together in `.onAppear`. `TabItem` also marked `@Observable` so mutations to `url`/`document` trigger SwiftUI re-renders.

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
