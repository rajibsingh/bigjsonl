# bigjsonl

A standalone, viewer-only tool for inspecting large JSONL (JSON Lines) files.

Each line in a JSONL file is displayed as an independent syntax-highlighted document, making it easy to rapidly scan through files that are too large to comfortably open in a general-purpose editor.

## Status

Early development (v0.1). Not yet functional.

## Architecture

- **BigJSONLCore** — shared library with zero external dependencies (line-offset index, mmap-based windowed reads, swift-json parsing, syntax token stream, grep/rg search)
- **bigjsonl-cli** — CLI tool using swift-argument-parser
- **BigJSONLApp** — SwiftUI macOS app (macOS 15+)

See [docs/PROJECT_VISION.md](docs/PROJECT_VISION.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for details.

## Building

```bash
swift build
swift test
swift run bigjsonl --help
```
