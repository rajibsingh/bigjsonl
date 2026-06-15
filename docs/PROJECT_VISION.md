# bigjsonl — Project Vision

## What this is

bigjsonl is a standalone, viewer-only tool for inspecting large JSONL (JSON Lines) files. Each line in a JSONL file is an independent JSON document, and bigjsonl displays each line as its own syntax-highlighted document, making it easy to rapidly scan and read through files that are too large to comfortably open in a general-purpose editor or JSON viewer.

This tool exists because working with large JSONL files — logs, model outputs, training data, transcripts, event streams — produces a sheer volume of text that becomes overwhelming to look through with standard tools. The goal is a fast, lightweight way to look at that data without friction.

## Why it's separate from Prestidigitator

This started as a need identified while working on Prestidigitator, but it's being built and shipped as its own thing. There appears to be broader need for this in the AI dev community (huge JSONL files are everywhere in that world — datasets, logs, eval outputs), and keeping it standalone means:

- It can be used independently of Prestidigitator, by anyone, for any JSONL file.
- It doesn't get tangled up with Prestidigitator's own scope, release cadence, or design decisions.
- If it's useful enough on its own, it can exist as a small focused tool with its own identity, without requiring an explanation of what Prestidigitator is.

The name is deliberately plain: **bigjsonl**. It should be self-explanatory — a tool for viewing big JSONL files — and require no elevator pitch.

## Core design principles

**Viewer only, no editing.** This is a read-only tool. Scope stays small and the implementation stays simple by never having to deal with write-back, conflict resolution, or file mutation. If you need to edit, use something else.

**Each line is its own document.** JSONL means each line is a complete, independent JSON value. bigjsonl parses and syntax-highlights each line individually for maximum readability — the unit of display is the line/document, not the file.

**Never load the whole file into memory.** Files in this use case can be multi-gigabyte. bigjsonl only loads the portion of the file needed for the current viewport/buffer. This is the central constraint that shapes the architecture.

**Seek by index, not by re-scanning.** Naively re-scanning from byte 0 to find line N on every scroll doesn't scale. On open (or lazily, as needed), bigjsonl builds a line-offset index — a mapping from line number to byte offset — so that jumping to any line is a direct seek, not a linear scan. This index is the shared primitive that both windowed navigation and search results sit on top of.

**Search via system utilities.** Rather than implementing search internally, bigjsonl shells out to grep (or ripgrep/rg if available, for speed and byte-offset support). Search results are translated through the line-offset index back into byte positions, and the viewport jumps to that point in the file.

**Graceful degradation on malformed lines.** Real-world JSONL files sometimes contain a line that isn't valid JSON (truncated writes, mixed content, etc.). bigjsonl should show such lines as raw text with a clear "invalid JSON" indicator, rather than crashing or skipping the line.

## Architecture: Swift Package with shared core

See `docs/ARCHITECTURE.md` for the complete design. This section covers the high-level structure.

```
bigjsonl/
├── Sources/
│   ├── BigJSONLCore/       ← shared library (zero external dependencies)
│   ├── bigjsonl-cli/       ← CLI tool (swift-argument-parser)
│   └── BigJSONLApp/        ← SwiftUI app (macOS 15+)
└── Package.swift
```

**`BigJSONLCore`** contains all file-handling logic: mmap-based windowed reads, lazy incremental line-offset index, swift-json parsing with token stream output, and grep/rg subprocess search. Both the CLI and GUI import this same library — no code duplication.

**`bigjsonl-cli`** is a thin command-line wrapper using `swift-argument-parser`. Syntax highlighting renders as ANSI escape codes from the shared token stream.

**`BigJSONLApp`** is a SwiftUI macOS app targeting macOS 15 (Sequoia). Uses `DocumentGroup` with an overridden read path that never loads the full file. Uses `@Observable`, `ScrollPosition`, and `Inspector`.

### Trade-off

This approach is **macOS-only**. If cross-platform support becomes a priority, a TUI in Go or Rust would be better suited. For an initial audience of AI devs on Macs, this covers the primary use case.

## What success looks like for v1

- Open a multi-GB JSONL file and have it feel instant — no upfront "loading file..." delay.
- Scroll through lines with syntax-highlighted JSON, one document per line, readable at a glance.
- Search the file (via grep/ripgrep) and jump directly to matching lines.
- Handle malformed lines without breaking the viewing experience.
- Works as both a CLI tool (`bigjsonl ./path/to/file.jsonl`) and a native macOS SwiftUI app.

### Settled design decisions

The following questions are now decided and documented in `docs/ARCHITECTURE.md`:

- **Line-offset index**: Lazy incremental — start empty, extend as the user navigates.
- **Search**: grep auto-detected, ripgrep as optional fast-path. Never a hard dependency.
- **Index persistence**: Not persisted in v0.1 — rebuilt per session.
- **SwiftUI document model**: `DocumentGroup` with overridden read path. Worth the extra work for native macOS integration.
- **Token model**: Standardized in the core as a UI-agnostic `[Token]` array. CLI renders via ANSI, SwiftUI via `AttributedString`.
- **JSON parsing**: `swift-json` (lightweight, no Foundation dependency in the parsing path).

## Open questions / not yet decided

- Line wrapping / soft wrap for lines that exceed the viewport width.
- File watching / live reload for log files.
- Preferences UI (color schemes, font size, etc.).
- Index persistence — revisit post-v0.1 if users report slow opens on very large files.
