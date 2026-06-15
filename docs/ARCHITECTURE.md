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

#### Search

- Text field in the toolbar; on submit shells out to grep/rg via the core library's search module
- Results (capped at 500) replace the line list in the left pane — `SearchResultsView` shows line number gutter and a snippet with the matched term highlighted in orange
- Clicking a result jumps the viewport to that line via `ScrollPosition`; results stay visible so the user can navigate freely between matches without re-running the search
- A × button in the toolbar clears the query and results, restoring the line list
- Pane switching is driven off `searchResults.isEmpty` — no separate `searchActive` flag needed
- `clearSearch()` on `DocumentViewModel` resets query, results, and error state in one call

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
| 2026-06-15 | Search results replace the line list in the left pane rather than a separate column | Avoids invasive `NavigationSplitView` restructuring; the existing two-column layout (line list + inspector) is preserved with a clean swap. |
| 2026-06-15 | CLI formula shipped to `Sepoy-Software/tap`; Cask deferred | CLI can build without code signing. GUI Cask requires Apple Developer ID cert, CI notarization, and a signed release archive. |

## Distribution

### Homebrew CLI formula

The CLI is available via the `Sepoy-Software/tap` Homebrew tap:

```bash
brew tap Sepoy-Software/tap
brew trust sepoy-software/tap
brew install bigjsonl
```

The formula lives at `Formula/bigjsonl.rb` in [Sepoy-Software/homebrew-tap](https://github.com/Sepoy-Software/homebrew-tap). It builds from the tagged source archive (`v0.1.0`), requires Xcode 16+ at build time, and enforces the macOS 15 deployment target.

### Homebrew Cask (pending)

The GUI app requires a signed and notarized `.app` bundle to avoid Gatekeeper dialogs on first launch. Prerequisites before publishing the Cask:

- Apple Developer account and a valid Developer ID Application certificate
- A CI signing and notarization step (e.g., GitHub Actions with `xcrun notarytool`)
- A versioned `.dmg` or `.zip` archive hosted as a GitHub release asset

Once those are in place, add `Casks/bigjsonl.rb` to the tap pointing at the signed archive.

## TODO

### Tabbed interface

**Goal.** Allow the user to have multiple JSONL files open simultaneously in a single window, each in its own tab. Opening a new tab shows the welcome screen (file picker prompt) so the user can select a file. Each tab is fully independent — its own viewport, index, search state, and inspector.

**Analysis.**

The current app uses a single `WindowGroup` with one `documentURL: URL?` state variable. Each file replaces the previous one. `NSWindow.allowsAutomaticWindowTabbing = false` is set explicitly in `init()` to suppress macOS's automatic tab merging — this will need to be removed or selectively overridden.

There are two viable approaches:

1. **Native macOS automatic tabbing** — remove `allowsAutomaticWindowTabbing = false` and let macOS merge new `WindowGroup` windows into tabs automatically. Each tab is a full `WindowGroup` window. Simple to implement but gives limited control over tab creation UX (new tab opens a file picker without a welcome screen unless handled carefully) and tab bar appearance.

2. **Custom tab bar in SwiftUI** — manage an array of open documents in app state, render a custom tab strip at the top of the window, and swap `ContentView` based on the selected tab index. Full control over UX; more code.

**Recommended approach: custom tab bar.** Native tabbing is convenient but leaks state management — each "tab" is actually a separate window with its own `WindowGroup` lifecycle, making it hard to share a tab bar, synchronize selection, or add a + button that opens the welcome screen. A custom tab bar keeps all state in one place and matches the desired UX exactly.

**Thumbnail plan.**

| Step | Work |
|------|------|
| 1 | Define a `TabItem` model in `BigJSONLApp.swift`: `id: UUID`, `url: URL?`, `document: BigJSONLDocument?`. A `nil` URL represents a new/empty tab showing the welcome screen. |
| 2 | Add `@State private var tabs: [TabItem]` and `@State private var selectedTabID: UUID` to `BigJSONLApp`. Initialize with one empty tab on launch. |
| 3 | Build `TabBarView` — a horizontal `HStack` of tab chips showing the filename (or "New Tab" for empty tabs), with a × close button on each and a + button at the right end. Selecting a chip sets `selectedTabID`; the + button appends a new empty `TabItem`. |
| 4 | Replace the current `WindowGroup` body with `TabBarView` above a `ZStack`/`switch` that renders `ContentView(document:)` for the selected tab's document, or the welcome screen if the tab has no URL. |
| 5 | When the welcome screen's "Open File…" button is called from within a tab context, assign the chosen URL to the current tab's `TabItem` rather than a top-level `documentURL`. |
| 6 | Remove `NSWindow.allowsAutomaticWindowTabbing = false` from `init()` (or keep it — with a custom tab bar, native tabbing is irrelevant and can stay suppressed). |
| 7 | Handle close: closing the last tab either shows an empty welcome tab or quits the app (match macOS convention — keep at least one window open). |

**State ownership note.** Each `TabItem` owns its `BigJSONLDocument` (and therefore its `LineOffsetIndex` and `MappedFile`). `DocumentViewModel` is created per-tab inside `ContentView` as today — no changes needed to the view model or core library.
