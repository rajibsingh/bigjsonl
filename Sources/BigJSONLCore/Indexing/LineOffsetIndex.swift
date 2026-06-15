import Foundation
import Dispatch

/// A lazy, incremental mapping from 1-based line numbers to byte offsets
/// within a JSONL file.
///
/// The index starts empty and extends itself forward as lines are requested.
/// Jumping to an unindexed line scans forward from the last known position
/// using the provided `MappedFile`.
///
/// Line boundaries are detected by scanning for `\n`. Carriage returns (`\r`)
/// before newlines are handled gracefully (they're included in the line but
/// don't create extra line entries).
public struct LineOffsetIndex: Sendable {
    /// Sorted array of (lineNumber, byteOffset) pairs, 1-based.
    /// Each entry records the byte offset of the *start* of that line.
    private var entries: [(UInt64, UInt64)] = []
    private var scanOffset: UInt64 = 0
    private var reachedEOF = false

    /// Creates an empty index.
    public init() {}

    /// The highest line number that has been indexed so far, or nil if empty.
    public var lastIndexedLine: UInt64? {
        entries.last?.0
    }

    /// The total number of lines discovered so far.
    /// This is an upper bound — the file may have more lines that haven't been
    /// scanned yet.
    public var lineCount: UInt64 {
        entries.last?.0 ?? 0
    }

    /// Whether the index has scanned through the end of the file.
    public var isComplete: Bool {
        reachedEOF
    }

    /// Returns the byte offset for a given line, if it has been indexed.
    /// - Parameter line: 1-based line number.
    /// - Returns: The byte offset of the start of the line, or nil if not indexed.
    public func offsetForLine(_ line: UInt64) -> UInt64? {
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

    /// Ensures that the given line has been indexed, scanning forward from the
    /// last known position if necessary.
    ///
    /// After calling this, `offsetForLine(line)` is guaranteed to return a value
    /// (or the line is beyond EOF, in which case `lineCount < line`).
    ///
    /// - Parameters:
    ///   - line: 1-based line number to index.
    ///   - mappedFile: The memory-mapped file to scan.
    public mutating func ensureLineIndexed(_ line: UInt64, mappedFile: MappedFile) {
        guard line > 0 else { return }
        if offsetForLine(line) != nil { return }

        let fileSize = mappedFile.size
        guard fileSize > 0 else {
            reachedEOF = true
            return
        }

        if entries.isEmpty {
            entries.append((1, 0))
        }

        while entries.last!.0 < line && scanOffset < fileSize {
            let chunkSize: UInt64 = min(256 * 1024, fileSize - scanOffset) // 256KB chunks
            let chunk = mappedFile.read(offset: scanOffset, length: chunkSize)

            // Scan the chunk for newlines using byte array access
            let bytes = [UInt8](Data(chunk))

            for byte in bytes {
                scanOffset += 1
                if byte == UInt8(ascii: "\n"), scanOffset < fileSize {
                    let nextLine = entries.last!.0 + 1
                    entries.append((nextLine, scanOffset))
                    if nextLine == line {
                        return
                    }
                }
            }
        }

        if scanOffset == fileSize {
            reachedEOF = true
        }
    }

    /// Returns the byte range of the given line, if indexed.
    ///
    /// The range spans from the start of the line to the start of the next line,
    /// or to the end of the file for the last line. The range includes the
    /// trailing newline byte (if any).
    ///
    /// - Parameters:
    ///   - line: 1-based line number.
    ///   - fileSize: Total file size, used to compute the end of the last line.
    /// - Returns: The byte range of the line, or nil if the line is not indexed.
    public func byteRangeForLine(_ line: UInt64, fileSize: UInt64) -> Range<UInt64>? {
        guard let start = offsetForLine(line) else { return nil }

        if let nextOffset = offsetForLine(line + 1) {
            return start..<nextOffset
        }

        return reachedEOF ? start..<fileSize : nil
    }
}
