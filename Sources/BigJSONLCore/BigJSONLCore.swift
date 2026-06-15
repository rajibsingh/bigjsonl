// BigJSONLCore — shared library for bigjsonl
//
// This module contains all file-handling logic: mmap-based windowed reads,
// lazy incremental line-offset index, swift-json parsing with token stream
// output, and grep/rg subprocess search. Both the CLI and SwiftUI app import
// this library.

// MARK: - Re-export public API

@_exported import struct Foundation.URL
