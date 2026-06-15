# bigjsonl — Architecture

## Target Platform

- **macOS 15 (Sequoia)** — unlocks `@Observable`, `@Entry`, `ScrollPosition`, `Inspector`, and Swift 6 strict concurrency
- **Swift 6** — latest language with complete data-race safety
- No Linux or Windows support planned (SwiftUI is Apple-platform-only)

## Project Structure

```
bigjsonl/
├── Sources/
│   ├── BigJSONLCore/       ← shared library (zero external dependencies)
│   │   ├── FileIO/         ← mmap, windowed reads, line boundaries
│   │   ├── Indexing/       ← LineOffsetIndex (lazy incremental)
│   │   ├── Parsing/        ← swift-json integration, token stream
│   │   ├── Search/         ← grep/rg subprocess wrapper
│   │   └── Models/         ← Token, TokenType, LineInfo, SearchResult
│   ├── bigjsonl-cli/       ← CLI tool (depends on swift-argument-parser)
│   │   └── BigJSONL.swift  ← @main ParsableCommand
│   └── BigJSONLApp/        ← SwiftUI app (system frameworks only)
│       ├── BigJSONLApp.swift
│       ├── Views/
│       │   ├── ContentView.swift
│       │   ├── LineView.swift          ← compact plain-text line rendering
│       │   ├── SyntaxHighlightedTextView.swift ← AppKit-backed inspector rendering
│       │   └── SearchPanel.swift
│       ├── ViewModel/
│       │   └── DocumentViewModel.swift ← @Observable, bridges core to UI
│       └── Document/
│           └── BigJSONLDocument.swift  ← DocumentGroup override
├── Tests/
│   ├── BigJSONLCoreTests/
│   │   ├── LineOffsetIndexTests.swift
│   │   ├── MappedFileTests.swift
│   │   ├── JSONTokenizerTests.swift
│   │   └── SearcherTests.swift
│   └── BigJSONLAppTests/
│       └── DocumentViewModelTests.swift
├── test-files/             ← real JSONL data for manual testing
├── Package.swift
├── CHANGELOG.md
├── AGENTS.md
└── docs/
    ├── PROJECT_VISION.md
    └── ARCHITECTURE.md
```

## Target Dependency Graph

```
BigJSONLCore  ←  zero external dependencies
     ↑                ↑
     |                |
bigjsonl-cli    BigJSONLApp
     |                |
swift-arg-     SwiftUI +
   parser        AppKit
                (system)
```

- `BigJSONLCore` has **zero dependencies** — only `Foundation` and `Dispatch` (system frameworks)
- `bigjsonl-cli` depends on `swift-argument-parser` (Apple-maintained, lightweight)
- `BigJSONLApp` depends only on system frameworks: SwiftUI, AppKit, UniformTypeIdentifiers
- The SwiftPM executable embeds `Sources/BigJSONLApp/Info.plist` in its Mach-O
  `__TEXT,__info_plist` section, disables automatic window tabbing, and opts into
  AppKit's regular activation policy, so Xcode launches it as a foreground GUI
  app with bundle metadata for `com.rajibsingh.bigjsonl`

## Data Flow

### Opening a file

```
User opens file
       │
       ▼
Store file URL (don't read yet)
       │
       ▼
Create empty LineOffsetIndex
       │
       ▼
Read first window of lines (viewport buffer)
       │
       ▼
For each line in window:
    ├── Parse with swift-json
    └── Append plain text and validity to line cache for display
```

### Scrolling (line N)

```
User scrolls to line N
       │
       ▼
LineOffsetIndex.hasLine(N)?
       ├── Yes → seek to byte offset, read window
       └── No  → byte-scan from last indexed position to N
                    └── Append entries to LineOffsetIndex
       │
       ▼
Read a bounded overlapping window
       │
       ▼
Edge sentinels shift the window while preserving a stable anchor
```

### Search

```
User enters search query
       │
       ▼
Shell out: grep/rg --byte-offset --line-number <pattern> <file>
       │
       ▼
Parse capped output → [(lineNumber, byteOffset)]
       │
       ▼
Translate through LineOffsetIndex → absolute byte positions
       │
       ▼
Jump viewport to first match (or show result list)
```

## Key Components

### BigJSONLCore

#### FileIO

- Uses `mmap` via `DispatchData` for zero-copy access to file regions
- No-copy `DispatchData` regions retain their `MappedFile` owner so the mapping
  cannot be unmapped while a returned slice is still alive
- Provides `FileRegion(url:, offset:, length:)` — a lightweight reference to a byte range
- Handles line-boundary detection (newline, carriage-return-newline, trailing newline edge cases)
- Exposes `totalFileSize` and `numberOfNewlines` (the latter from the index, not a full scan)

```swift
struct FileRegion {
    let url: URL
    let offset: UInt64
    let length: UInt64
    var data: DispatchData { get }
}
```

#### Indexing — LineOffsetIndex

- **Strategy: lazy incremental** — start empty, extend as the user navigates
- Tracks whether EOF has been reached; a line range is available only when its
  next-line boundary or the physical EOF is known
- Stores a sorted array of `(lineNumber: UInt64, byteOffset: UInt64)` pairs
- On `seek(toLine:)`: if the line is indexed, use it; if not, scan forward from the last indexed byte offset until the target line is reached
- `readWindow(fromLine:count:)` returns `[FileRegion]` — one per line in the window
- Index can be serialized/deserialized for future persistence but isn't persisted in v0.1

```swift
struct LineOffsetIndex {
    private var entries: [(UInt64, UInt64)]  // (lineNumber, byteOffset)

    mutating func ensureLineIndexed(_ line: UInt64, fileHandle: FileHandle)
    func offsetForLine(_ line: UInt64) -> UInt64?
    var lastIndexedLine: UInt64? { get }
    var lineCount: UInt64 { get }
}
```

#### Parsing — Token Stream

- Uses **swift-json** for per-line parsing
- `tokenize(_:)` produces a flat array of tokens ordered by byte position within the line
- `JSONFormatter.prettyPrinted(_:)` adds structural indentation and line breaks
  while preserving string contents, literal spelling, and object key order

```swift
enum TokenType: Equatable {
    case punctuation   // { } [ ] , :
    case key           // "keyName"
    case stringValue   // "some value"
    case number        // 42, 3.14, -1e5
    case bool          // true, false
    case null          // null
    case invalid       // raw text for malformed lines
}

struct Token: Equatable {
    let range: Range<UInt64>  // byte range within the line
    let type: TokenType
}
```

- For malformed lines: `tokenize` returns a single `Token` with type `.invalid` spanning the entire line. The line text is preserved as-is; no crash, no skip.
- The token model is **UI-agnostic** — both the CLI and SwiftUI app consume the same `[Token]` array and render it in their respective medium (ANSI codes vs. `AttributedString`).

#### Search — Grep/Rg Wrapper

- Auto-detects `rg` (ripgrep) on `$PATH`; falls back to `grep`
- Always requests `--byte-offset` and `--line-number`
- Caps subprocess output at the requested result limit (500 by default)
- Provides an async entry point that terminates the subprocess on task cancellation
- Treats subprocess status 1 as a successful search with no matches
- Result type:

```swift
struct SearchResult {
    let lineNumber: UInt64
    let byteOffset: UInt64
    let lineText: String
}
```

### bigjsonl-cli

- Single `@main` command with flags:

```
USAGE: bigjsonl <file> [--line <n>] [--search <pattern>] [--no-color]
```

- Renders lines to stdout with ANSI color codes derived from `TokenType`
- Shows a line-number gutter (e.g., ` 42 │ { ... }`)
- If `--search` is provided, opens to the first match and highlights matches inline
- If `--line` is provided, jumps to that line
- Pager mode: pipe through `less -R` automatically if stdout is a TTY

### BigJSONLApp

#### DocumentGroup with lazy loading

- Uses `DocumentGroup` for native macOS document integration (recent files, drag-and-drop, title bar filename)
- Overrides `read(from:ofType:)` in `BigJSONLDocument` — instead of loading file data into memory, stores the file URL and initializes an empty state
- `DocumentViewModel` (`@Observable`) manages the scroll position, viewport buffer, and search state

```swift
class BigJSONLDocument: ReferenceFileDocument {
    let url: URL
    let index = LineOffsetIndex()
    // read(from:ofType:) does NOT load file data — just validates existence
}
```

#### Scroll-driven viewport

- Uses `ScrollPosition` binding (macOS 15) for programmatic scrolling to search results
- Renders only a bounded overlapping line window
- An end-of-user-scroll geometry check loads the previous or next window and
  preserves a shared line ID as the scroll anchor, allowing continuous navigation
  without mutating viewport state during initial layout
- Each line is rendered as plain monospace text; viewport rows do not build an
  unused syntax token stream
- Line rows are limited to three visual lines with tail truncation so a single
  large JSON value cannot dominate the scrolling viewport

#### Search panel

- Text field at the top of the window or in a toolbar
- On submit: shells out to grep/rg via the core library's search module
- Shows results as a list with line numbers and a text snippet
- Clicking a result scrolls the viewport to that line via `ScrollPosition`

#### Line inspector

- Metadata remains fixed above a full-height `Content` pane
- Valid JSON is pretty-printed and tokenized in a detached task so selecting a
  large record does not block the main actor; stale results are discarded
- Prepared content is retained in a three-entry cache for fast reselection
- An AppKit `NSTextView` renders a single attributed string instead of creating
  one SwiftUI `Text` node per syntax token; ASCII records use token byte ranges
  directly as UTF-16 ranges
- Invalid JSON is shown unchanged and remains selectable

#### Malformed lines

- Visually distinct background tint (e.g., subtle red/orange)
- Indicator badge or icon next to the line number
- All text rendered as-is in a monospace font

## What's Not in the MVP (v0.1)

| Feature | Rationale |
|---------|-----------|
| Index persistence to disk | Rebuilding per session is fine for v0.1; revisit if users report slow opens on very large files |
| ripgrep as a hard dependency | Auto-detect with graceful grep fallback — less friction for users who don't have rg |
| Line wrapping / soft wrap | Each line can exceed terminal width / window width; wrapping adds complexity. Deferred. |
| File watching (live reload) | Useful for log files but adds complexity. Post-v1. |
| Multi-file tabs | Single-file viewer for v0.1. Post-v1. |
| Preferences UI | Colors, font size, etc. can be hardcoded for v0.1. |

## Design Decisions Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-06-15 | macOS 15 deployment target | Unlocks `@Observable`, `ScrollPosition`, `Inspector`, Swift 6. Audience of AI devs on recent Macs. |
| 2026-06-15 | Lazy incremental line-offset index | Minimizes startup time — no upfront scan. Index grows as user navigates. |
| 2026-06-15 | swift-json for JSON parsing | Streaming-friendly, fast, no Foundation dependency in the parsing path. |
| 2026-06-15 | Shared Token/TokenType model in core | Both CLI and SwiftUI app consume the same token stream; each renders in its own medium. |
| 2026-06-15 | DocumentGroup for SwiftUI app | Worth the extra work — gives native macOS document integration (recent files, drag-drop, title bar). |
| 2026-06-15 | grep/ripgrep search via subprocess | Avoids implementing search internally. System utilities are fast, well-tested, and handle edge cases. |
| 2026-06-15 | mmap via DispatchData for file access | Zero-copy windowed reads — no unnecessary memory allocation for visible lines. |
| 2026-06-15 | Raw UTF-8 byte tokenizer instead of swift-json AST walking | swift-json doesn't preserve source byte positions. Tokenizer validates with swift-json, then scans raw bytes for accurate positions. |
| 2026-06-15 | `MappedFile` maps entire file, `DispatchData` references sub-regions | Single mmap avoids per-region overhead. Each no-copy region retains the mapping owner without deallocating the mapped pointer. |
| 2026-06-15 | Trailing newline at EOF doesn't create a line entry | Prevents off-by-one when the last byte of the file is `\n`. |
| 2026-06-15 | Line ranges require lookahead or confirmed EOF | Prevents a partially indexed boundary line from reading through the remainder of a large file. |
| 2026-06-15 | Search results are capped and asynchronously cancellable | Keeps broad searches from blocking the app or consuming memory proportional to all matches. |
| 2026-06-15 | Scroll navigation uses bounded overlapping windows | End-of-user-scroll geometry checks enable continuous browsing while avoiding state mutation during initial SwiftUI layout. |
| 2026-06-15 | Inspector preparation runs off the main actor and uses AppKit text rendering | Keeps selection responsive for content-heavy records while preserving selectable syntax-highlighted output. |

## TODO

### 1. Package for distribution through Homebrew

**Analysis.** Bigjsonl currently has no distribution mechanism beyond building from source via `swift build`. A Homebrew formula would give users a one-command install (`brew install bigjsonl`), auto-manage dependencies, and provide straightforward upgrade paths. The project produces two binaries — `bigjsonl` (CLI) and `BigJSONLApp` (GUI app) — both of which could be distributed through a single formula.

Key considerations:
- **Build from source** — SwiftPM resolves dependencies (swift-json, swift-argument-parser) at build time; the formula needs `swift build -c release` as its build step. macOS 15 (Xcode 16+) is a build dependency.
- **Two output artifacts** — The CLI (`bigjsonl`) can be installed directly into `/usr/local/bin`. The GUI app (`BigJSONLApp`) should be bundled as a `.app` in `/Applications`. The formula can define multiple `keg_only` outputs or use a `brew` `cask` for the GUI alongside the CLI formula.
- **Code signing** — Homebrew does not sign binaries; users on Apple Silicon will see a Gatekeeper dialog on first launch for the GUI app. A signed `.app` bundle would need an Apple Developer account and CI signing step.
- **Versioning** — Formula revision tracks the git tag. The existing SemVer convention (CHANGELOG, git tags) maps directly.

**Thumbnail plan.**

| Step | Work |
|------|------|
| 1 | Create `Formula/bigjsonl.rb` with `desc`, `homepage`, `url`, `sha256`, `depends_on :xcode`.
| 2 | Set `install` to `system "swift", "build", "-c", "release", "--product", "bigjsonl"` then `bin.install ".build/release/bigjsonl"`.
| 3 | Optionally add a second output for the GUI: build `--product BigJSONLApp`, create a minimal `.app` bundle skeleton, and offer a `brew` `cask` or a caveat directing the user to build it manually.
| 4 | Tag a release (`git tag v0.1.0`), compute the source archive SHA256, update the formula.
| 5 | Test with `brew install --build-from-source Formula/bigjsonl.rb`.
| 6 | Submit to `homebrew-core` (CLI only) or maintain as a tap (`rajibsingh/tap/bigjsonl`) for faster iteration.

The formula should live in a `Formula/` directory at the repo root and be referenced from `README.md` once published.

---

### 2. Improved search with left-pane results list

**Analysis.** The current search implementation (toolbar text field → grep/rg → jump to first match) is minimal: it shows a single result at a time and provides no way to browse across matches. The desired UX is a persistent search results pane on the left side of the window showing every matching line (line number + snippet), with click-to-navigate, similar to Xcode's find navigator or VS Code's search sidebar.

Several architectural constraints make this non-trivial:

1. **Viewport vs. results list** — The visible line buffer is a finite window around the current scroll position. Search results are potentially scattered across the entire file. Clicking a result needs to scroll the viewport to that exact line, which is already supported (the index can seek by offset).

2. **Memory** — A broad search over a multi-GB file could match thousands of lines. Each match includes line text (potentially ~100 KB per line). We need to cap results (already done: 500 limit) but also avoid loading every matching line's text eagerly into a large array.

3. **UITK reconciliation** — The current layout uses `NavigationSplitView` where the primary pane is the scrollable line list and the detail pane is the line inspector. Search results need their own pane. Options:
   - **Re-task the sidebar** — When search is active, replace the line list with a search results list; selecting a result scrolls the viewport (which becomes the detail pane).
   - **Separate floating panel** — A `NSPanel` or SwiftUI `.popover` overlay that floats above the viewport.
   - **Three-column layout** — Use a true `NavigationSplitView` with sidebar (results), content (line list), and detail (inspector). This is the most natural fit but the most invasive change.

4. **Lazy loading of result lines** — The grep/rg subprocess returns `(lineNumber, byteOffset, lineText)` for each match. The `lineText` field already contains the full text (capped by the result limit). We can display snippets from this text directly without extra I/O. For the full syntax-highlighted view (when the user clicks a result), we read the line through the normal viewport path, tokenize it, and render it — same as any other line.

**Thumbnail plan.**

| Step | Work |
|------|------|
| 1 | Add a `searchActive` state and `searchResults: [SearchResult]` array to `DocumentViewModel`. Currently results are stored but not surfaced beyond `scrollTo(firstMatch)`. Keep the 500-match cap and async subprocess from the code review fixes.
| 2 | Design the search results pane UI in its own SwiftUI view (`SearchResultsView`). Show line number in a gutter + a one-line snippet (trimmed to ~200 chars). Highlight the search pattern within the snippet.
| 3 | Integrate the pane into `ContentView`'s `NavigationSplitView`. Best approach: when `searchActive`, replace the line list (`ScrollView` → `LazyVStack`) with a `List` of search results. Selecting a result calls `scrollTo(line:)` and switches back to the line list scrolled to that line, with the matched line highlighted.
| 4 | Handle the back-navigation: after clicking a result and landing on a line, the user should be able to return to the results list without re-running the search. Keep search results cached in the view model until the query changes or is cleared.
| 5 | Test with broad patterns (e.g., `"event"` matching most lines in a file), edge cases (no matches, exactly 500 matches, pattern with regex special chars).

Down the road, the left pane could evolve into a proper sidebar with togglable modes (file outline vs. search results vs. bookmarks), but a single-purpose search results pane is the right v0.2 increment.
