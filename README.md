# bigjsonl

A standalone, viewer-only tool for inspecting large JSONL (JSON Lines) files.

Each line in a JSONL file is displayed as an independent syntax-highlighted document, making it easy to rapidly scan through files that are too large to comfortably open in a general-purpose editor.

## Status

v0.1.0 — CLI functional. SwiftUI app in active development.

## Installation

### Homebrew (recommended)

```bash
brew tap Sepoy-Software/tap
brew trust sepoy-software/tap
brew install bigjsonl
```

### Build from source

Requires Xcode 16+ and macOS 15.

```bash
git clone https://github.com/rajibsingh/bigjsonl.git
cd bigjsonl
swift build -c release --product bigjsonl
.build/release/bigjsonl --help
```

## Usage

```bash
bigjsonl path/to/file.jsonl
bigjsonl path/to/file.jsonl --line 42
bigjsonl path/to/file.jsonl --search "error"
bigjsonl path/to/file.jsonl --no-color
```

## Features

- Opens multi-GB JSONL files instantly — no upfront file load
- Multiple files open simultaneously in tabs (⌘T for new tab, ⌘O to open one or more files)
- Scrollable line list with one document per line; inspector auto-opens on the first line
- `\n` escape sequences in JSON strings displayed as visible markers with real line breaks for readability
- Search via grep/ripgrep — results appear in a persistent left-pane list; click any result to jump to that line; query persists across tab switches
- Line inspector sidebar showing byte offset, length, JSON validity, and pretty-printed syntax-highlighted content
- Graceful handling of malformed lines (shown as raw text with a visual indicator)
- Available as both a CLI tool and a native macOS SwiftUI app

## Architecture

- **BigJSONLCore** — shared library with zero external dependencies (line-offset index, mmap-based windowed reads, swift-json parsing, syntax token stream, grep/rg search)
- **bigjsonl-cli** — CLI tool using swift-argument-parser
- **BigJSONLApp** — SwiftUI macOS app (macOS 15+)

See [docs/PROJECT_VISION.md](docs/PROJECT_VISION.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for details.
