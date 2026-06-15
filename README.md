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

## Architecture

- **BigJSONLCore** — shared library with zero external dependencies (line-offset index, mmap-based windowed reads, swift-json parsing, syntax token stream, grep/rg search)
- **bigjsonl-cli** — CLI tool using swift-argument-parser
- **BigJSONLApp** — SwiftUI macOS app (macOS 15+)

See [docs/PROJECT_VISION.md](docs/PROJECT_VISION.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for details.
