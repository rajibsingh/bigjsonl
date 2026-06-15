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
│       │   ├── LineView.swift          ← syntax-highlighted line rendering
│       │   └── SearchPanel.swift
│       ├── ViewModel/
│       │   └── DocumentViewModel.swift ← @Observable, bridges core to UI
│       └── Document/
│           └── BigJSONLDocument.swift  ← DocumentGroup override
├── Tests/
│   ├── BigJSONLCoreTests/
│   │   ├── LineOffsetIndexTests.swift
│   │   ├── TokenizerTests.swift
│   │   └── SearchTests.swift
│   └── BigJSONLAppTests/
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
    ├── Tokenize → [Token] (colors, structure)
    └── Append to line cache for display
```

### Scrolling (line N)

```
User scrolls to line N
       │
       ▼
LineOffsetIndex.hasLine(N)?
       ├── Yes → seek to byte offset, read window
       └── No  → byte-scan from last indexed position to N
                    ├── Append entries to LineOffsetIndex
                    └── seek to byte offset, read window
```

### Search

```
User enters search query
       │
       ▼
Shell out: grep/rg --byte-offset --line-number <pattern> <file>
       │
       ▼
Parse output → [(lineNumber, byteOffset)]
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
- Renders only the visible lines + a small buffer above/below
- Each line is rendered as a `LineView` that applies `AttributedString` styles from the token stream

#### Search panel

- Text field at the top of the window or in a toolbar
- On submit: shells out to grep/rg via the core library's search module
- Shows results as a list with line numbers and a text snippet
- Clicking a result scrolls the viewport to that line via `ScrollPosition`

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
