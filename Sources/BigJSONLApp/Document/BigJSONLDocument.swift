import Foundation
import BigJSONLCore

/// A lightweight document model that represents a JSONL file.
///
/// Stores only the file URL — the file contents are loaded lazily through
/// the `DocumentViewModel` using mmap-based windowed reads.
final class BigJSONLDocument: @unchecked Sendable {
    /// The URL of the file on disk.
    let url: URL

    /// The lazy incremental line-offset index for this file.
    var index: LineOffsetIndex

    init(url: URL) {
        self.url = url
        self.index = LineOffsetIndex()
    }
}
