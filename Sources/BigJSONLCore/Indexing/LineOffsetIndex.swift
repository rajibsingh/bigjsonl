import Foundation
import Dispatch

/// Holds per-chunk results written from `DispatchQueue.concurrentPerform`.
/// Safe as `@unchecked Sendable` because each chunk index is written by
/// exactly one concurrent iteration and never read until all iterations
/// complete.
private final class ChunkResultsBox: @unchecked Sendable {
    private var storage: [[UInt64]]

    init(count: Int) {
        storage = [[UInt64]](repeating: [], count: count)
    }

    func store(_ offsets: [UInt64], at index: Int) {
        storage[index] = offsets
    }

    var values: [[UInt64]] { storage }
}

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

        // A short forward scan (the common incremental case — the user has
        // scrolled a bit further) stays on the single-pass byte scanner: it
        // stops as soon as the target line is found, so it doesn't waste work
        // scanning past it.
        let remaining = fileSize - scanOffset
        if remaining <= Self.parallelScanThreshold {
            scanSequentially(upTo: line, fileSize: fileSize, mappedFile: mappedFile)
            return
        }

        // A long-distance jump (e.g. opening near EOF of a multi-GB file) has
        // to scan a large span regardless of where the target line lands, so
        // counting newlines in disjoint byte chunks in parallel pays off. The
        // per-chunk counts are merged back into `entries` sequentially since
        // line numbers are a prefix sum over newline counts.
        scanInParallel(upTo: line, fileSize: fileSize, mappedFile: mappedFile)
    }

    /// Below this many remaining bytes, scanning forward in parallel chunks
    /// has more overhead (task spawn, per-chunk array allocation) than it
    /// saves versus the single-pass scanner.
    private static let parallelScanThreshold: UInt64 = 4 * 1024 * 1024

    private mutating func scanSequentially(upTo line: UInt64, fileSize: UInt64, mappedFile: MappedFile) {
        while entries.last!.0 < line && scanOffset < fileSize {
            let chunkSize: UInt64 = min(256 * 1024, fileSize - scanOffset) // 256KB chunks
            let foundTarget = mappedFile.withUnsafeBytes(offset: scanOffset, length: chunkSize) { bytes in
                for byte in bytes {
                    scanOffset += 1
                    if byte == UInt8(ascii: "\n"), scanOffset < fileSize {
                        let nextLine = entries.last!.0 + 1
                        entries.append((nextLine, scanOffset))
                        if nextLine == line {
                            return true
                        }
                    }
                }
                return false
            } ?? false

            if foundTarget {
                return
            }
        }

        if scanOffset == fileSize {
            reachedEOF = true
        }
    }

    /// Counts newlines from `scanOffset` to `fileSize` by splitting the span
    /// into disjoint chunks and scanning each chunk's byte range concurrently
    /// (read-only access into the mmap via `MappedFile.withUnsafeBytes`, safe
    /// across chunks since regions don't overlap). The per-chunk newline
    /// offsets are then merged into `entries` in chunk order — this merge
    /// must stay sequential because each line number depends on the count of
    /// newlines that came before it.
    private mutating func scanInParallel(upTo line: UInt64, fileSize: UInt64, mappedFile: MappedFile) {
        let scanStart = scanOffset
        let totalSpan = fileSize - scanStart
        let chunkCount = min(
            max(ProcessInfo.processInfo.activeProcessorCount, 1),
            Int((totalSpan + Self.parallelScanThreshold - 1) / Self.parallelScanThreshold)
        )
        let chunkSize = (totalSpan + UInt64(chunkCount) - 1) / UInt64(chunkCount)

        var chunkRanges: [Range<UInt64>] = []
        var chunkStart = scanStart
        while chunkStart < fileSize {
            let chunkEnd = min(chunkStart + chunkSize, fileSize)
            chunkRanges.append(chunkStart..<chunkEnd)
            chunkStart = chunkEnd
        }

        // Newline byte offsets within each chunk, found independently and
        // written into disjoint indices of a shared results box. Concurrent
        // writes never touch the same index, so this is safe despite the box
        // being `@unchecked Sendable`.
        let chunkRangesSnapshot = chunkRanges
        let results = ChunkResultsBox(count: chunkRangesSnapshot.count)
        DispatchQueue.concurrentPerform(iterations: chunkRangesSnapshot.count) { chunkIndex in
            let range = chunkRangesSnapshot[chunkIndex]
            var offsets: [UInt64] = []
            _ = mappedFile.withUnsafeBytes(offset: range.lowerBound, length: range.upperBound - range.lowerBound) { bytes in
                for (i, byte) in bytes.enumerated() where byte == UInt8(ascii: "\n") {
                    offsets.append(range.lowerBound + UInt64(i))
                }
            }
            results.store(offsets, at: chunkIndex)
        }
        let newlineOffsetsByChunk = results.values

        // Merge sequentially: each newline at offset `o` (with o < fileSize - 1,
        // matching the sequential scanner's "no entry for a trailing EOF
        // newline" rule) starts a new line at o + 1. The full span up to
        // fileSize was already scanned in parallel above, so the merge keeps
        // every entry it finds rather than stopping at the requested line —
        // that work has already been paid for and the index might as well
        // reflect it, matching the sequential scanner's EOF-reached state.
        for offsets in newlineOffsetsByChunk {
            for offset in offsets {
                let nextOffset = offset + 1
                guard nextOffset < fileSize else { continue }
                let nextLine = entries.last!.0 + 1
                entries.append((nextLine, nextOffset))
            }
        }

        scanOffset = fileSize
        reachedEOF = true
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
