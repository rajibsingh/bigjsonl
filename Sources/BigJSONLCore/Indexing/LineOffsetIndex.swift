import Foundation

/// A lazy, incremental mapping from 1-based line numbers to byte offsets
/// within a JSONL file.
///
/// The index starts empty and extends itself forward as lines are requested.
/// Jumping to an unindexed line scans forward from the last known position.
public struct LineOffsetIndex: Sendable {
    /// Sorted array of (lineNumber, byteOffset) pairs, 1-based.
    private var entries: [(UInt64, UInt64)] = []

    /// Creates an empty index.
    public init() {}

    /// The highest line number that has been indexed so far, or nil if empty.
    public var lastIndexedLine: UInt64? {
        entries.last?.0
    }

    /// The total number of lines discovered so far.
    public var lineCount: UInt64 {
        entries.last?.0 ?? 0
    }

    /// Returns the byte offset for a given line, if it has been indexed.
    public func offsetForLine(_ line: UInt64) -> UInt64? {
        // Binary search since entries are sorted by line number
        guard !entries.isEmpty else { return nil }
        var low = 0
        var high = entries.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let entry = entries[mid]
            if entry.0 == line {
                return entry.1
            } else if entry.0 < line {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return nil
    }

    /// Ensures that the given line has been indexed by scanning forward
    /// from the last indexed position using the provided file handle.
    ///
    /// This is the core incremental extension mechanism.
    public mutating func ensureLineIndexed(_ line: UInt64, fileHandle: FileHandle) throws {
        guard line > 0 else { return }
        if offsetForLine(line) != nil { return }

        let startOffset = entries.last?.1 ?? 0
        try fileHandle.seek(toOffset: startOffset)

        var currentLine = entries.last?.0 ?? 0
        if currentLine == 0 {
            // Line 1 starts at offset 0
            entries.append((1, 0))
            currentLine = 1
        }

        while currentLine < line {
            let data = fileHandle.readData(ofLength: 1_024_000) // 1MB chunks
            if data.isEmpty { break } // EOF

            let bytes = [UInt8](data)
            for byte in bytes {
                if byte == UInt8(ascii: "\n") {
                    currentLine += 1
                    if currentLine <= line {
                        entries.append((currentLine, startOffset + UInt64(entries.count)))
                    }
                }
            }
        }
    }
}
