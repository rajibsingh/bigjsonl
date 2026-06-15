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
- Test suite with 7 passing tests for core models and index.
- `docs/ARCHITECTURE.md` with full design documentation.
- `docs/PROJECT_VISION.md` with vision, principles, and settled design decisions.
- `AGENTS.md` with changelog-first development workflow.
- `CHANGELOG.md` with Keep a Changelog conventions.
- Test data files in `test-files/` (pi session logs).
