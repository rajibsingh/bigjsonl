import Testing
import Foundation
import BigJSONLCore

@Test("Empty index")
func emptyIndex() {
    let index = LineOffsetIndex()
    #expect(index.lastIndexedLine == nil)
    #expect(index.lineCount == 0)
}

@Test("Offset for line in empty index")
func offsetInEmptyIndex() {
    let index = LineOffsetIndex()
    #expect(index.offsetForLine(1) == nil)
    #expect(index.offsetForLine(100) == nil)
}

@Test("Line offset index builds correctly from test file")
func indexFromTestFile() throws {
    let fixture = try TemporaryJSONLFile()
    let file = try MappedFile(url: fixture.url)
    var index = LineOffsetIndex()

    // Index the first 3 lines
    index.ensureLineIndexed(3, mappedFile: file)

    #expect(index.lineCount >= 3)
    #expect(index.lastIndexedLine! >= 3)

    // Line 1 should start at offset 0
    let offset1 = index.offsetForLine(1)
    #expect(offset1 == 0)

    // Line 2 should follow line 1
    let offset2 = index.offsetForLine(2)
    let offset3 = index.offsetForLine(3)
    if let o1 = offset1, let o2 = offset2, let o3 = offset3 {
        #expect(o2 > o1)
        #expect(o3 > o2)
    }
}

@Test("Indexing beyond EOF goes to end")
func indexBeyondEOF() throws {
    let fixture = try TemporaryJSONLFile()
    let file = try MappedFile(url: fixture.url)
    var index = LineOffsetIndex()

    // Try to index line 1,000,000 (way beyond the file)
    index.ensureLineIndexed(1_000_000, mappedFile: file)

    // Should have indexed everything available
    let totalLines = index.lineCount
    #expect(totalLines > 0)
    #expect(totalLines < 1_000_000)

    // All lines should have valid offsets
    for line in 1...totalLines {
        #expect(index.offsetForLine(line) != nil)
    }
}

@Test("Byte ranges are valid")
func byteRanges() throws {
    let fixture = try TemporaryJSONLFile()
    let file = try MappedFile(url: fixture.url)
    var index = LineOffsetIndex()

    // Index all lines
    index.ensureLineIndexed(100, mappedFile: file)
    let totalLines = index.lineCount

    // Each line's byte range should be non-empty and within file bounds
    for line in 1...totalLines {
        let range = index.byteRangeForLine(line, fileSize: file.size)
        #expect(range != nil)
        if let r = range {
            #expect(r.lowerBound < file.size)
            #expect(r.upperBound <= file.size)
            #expect(r.lowerBound < r.upperBound)
        }
    }
}

@Test("Lines match expected byte offsets against newline scanning")
func lineOffsetsMatchNewlines() throws {
    let fixture = try TemporaryJSONLFile()
    let file = try MappedFile(url: fixture.url)
    var index = LineOffsetIndex()

    // Index all lines
    index.ensureLineIndexed(100, mappedFile: file)
    let totalLines = index.lineCount

    // Verify each line starts with '{'
    for line in 1...totalLines {
        if let offset = index.offsetForLine(line) {
            let firstByte = file.readByte(at: offset)
            #expect(firstByte == UInt8(ascii: "{"))
        }
    }
}

@Test("A line range requires a known next boundary or EOF")
func byteRangeRequiresLookahead() throws {
    let fixture = try TemporaryJSONLFile()
    let file = try MappedFile(url: fixture.url)
    var index = LineOffsetIndex()

    index.ensureLineIndexed(2, mappedFile: file)
    #expect(index.byteRangeForLine(2, fileSize: file.size) == nil)

    index.ensureLineIndexed(3, mappedFile: file)
    let range = index.byteRangeForLine(2, fileSize: file.size)
    #expect(range?.upperBound == index.offsetForLine(3))
}

@Test("Large file index built via parallel scan matches sequential scan")
func largeFileParallelScanMatchesSequential() throws {
    // Exceeds LineOffsetIndex's parallel-scan threshold (4 MB) so jumping
    // straight to a line near the end exercises the chunked concurrent
    // newline-counting path instead of the single-pass scanner.
    let lineCount = 100_000
    var contents = ""
    contents.reserveCapacity(lineCount * 60)
    for i in 1...lineCount {
        contents += "{\"line\":\(i),\"value\":\"padding-text-to-grow-the-file-\(i)\"}\n"
    }
    contents.removeLast() // no trailing newline, matching the other fixtures

    let fixture = try TemporaryJSONLFile(contents: contents)
    let file = try MappedFile(url: fixture.url)
    #expect(file.size > 4 * 1024 * 1024)

    var parallelIndex = LineOffsetIndex()
    let targetLine = UInt64(lineCount) - 5
    parallelIndex.ensureLineIndexed(targetLine, mappedFile: file)

    // The parallel scan always indexes at least up to the requested line —
    // it may index further (up to its bounded lookahead window, or through
    // EOF if the lookahead reaches the end of the file), but never less.
    #expect(parallelIndex.lineCount >= targetLine)

    // Spot-check lines up to and including the jump target against the
    // known byte layout.
    for line in [1, 2, Int(targetLine) - 1, Int(targetLine)] {
        let offset = parallelIndex.offsetForLine(UInt64(line))
        #expect(offset != nil)
        if let offset {
            let firstByte = file.readByte(at: offset)
            #expect(firstByte == UInt8(ascii: "{"))
        }
    }

    // Cross-check against the sequential scanner by indexing the same file
    // one line at a time (always within the non-parallel threshold), which
    // forces the single-pass path throughout.
    var sequentialIndex = LineOffsetIndex()
    for line in 1...targetLine {
        sequentialIndex.ensureLineIndexed(line, mappedFile: file)
    }

    for line in stride(from: 1, through: Int(targetLine), by: 997) {
        #expect(parallelIndex.offsetForLine(UInt64(line)) == sequentialIndex.offsetForLine(UInt64(line)))
    }
}

@Test("Parallel scan jumping to EOF indexes the whole file and marks it complete")
func largeFileParallelScanToEOF() throws {
    let lineCount = 100_000
    var contents = ""
    contents.reserveCapacity(lineCount * 60)
    for i in 1...lineCount {
        contents += "{\"line\":\(i),\"value\":\"padding-text-to-grow-the-file-\(i)\"}\n"
    }
    contents.removeLast()

    let fixture = try TemporaryJSONLFile(contents: contents)
    let file = try MappedFile(url: fixture.url)
    #expect(file.size > 4 * 1024 * 1024)

    var index = LineOffsetIndex()
    // Request a line far beyond EOF, forcing the parallel scanner to run out
    // of newlines and fall through to the EOF-reached state.
    index.ensureLineIndexed(UInt64(lineCount) + 1_000, mappedFile: file)

    #expect(index.lineCount == UInt64(lineCount))
    #expect(index.isComplete)
}

@Test("A jump well before EOF bounds the parallel scan instead of indexing the whole file")
func jumpBeforeEOFStaysBounded() throws {
    // Large enough that a jump near the start, even with the lookahead
    // buffer's doubling on undershoot, is very unlikely to reach EOF.
    let lineCount = 400_000
    var contents = ""
    contents.reserveCapacity(lineCount * 60)
    for i in 1...lineCount {
        contents += "{\"line\":\(i),\"value\":\"padding-text-to-grow-the-file-\(i)\"}\n"
    }
    contents.removeLast()

    let fixture = try TemporaryJSONLFile(contents: contents)
    let file = try MappedFile(url: fixture.url)
    #expect(file.size > 16 * 1024 * 1024)

    var index = LineOffsetIndex()
    index.ensureLineIndexed(2, mappedFile: file)

    #expect(index.offsetForLine(2) != nil)
    #expect(index.lineCount >= 2)
    #expect(index.lineCount < UInt64(lineCount))
    #expect(!index.isComplete)
}

@Test("Empty files contain zero indexed lines")
func emptyFileHasNoLines() throws {
    let fixture = try TemporaryJSONLFile(contents: "")
    let file = try MappedFile(url: fixture.url)
    var index = LineOffsetIndex()

    index.ensureLineIndexed(1, mappedFile: file)

    #expect(index.lineCount == 0)
    #expect(index.isComplete)
    #expect(index.byteRangeForLine(1, fileSize: file.size) == nil)
}

@Test("Repeated nearby long-distance jumps do not repeatedly rescan the same span")
func repeatedNearbyJumpsStayFast() throws {
    // Regression coverage for a bug where each call's early-stop advanced
    // `scanOffset` only to the found target's offset instead of to the full
    // scanned span, causing every subsequent call to redo an almost-identical
    // multi-megabyte parallel scan. Calling ensureLineIndexed once per line
    // across a file just over the parallel-scan threshold should complete
    // quickly, not take quadratic time.
    let lineCount = 100_000
    var contents = ""
    contents.reserveCapacity(lineCount * 60)
    for i in 1...lineCount {
        contents += "{\"line\":\(i),\"value\":\"padding-text-to-grow-the-file-\(i)\"}\n"
    }
    contents.removeLast()
    let fixture = try TemporaryJSONLFile(contents: contents)
    let file = try MappedFile(url: fixture.url)
    #expect(file.size > 4 * 1024 * 1024)

    var index = LineOffsetIndex()
    let start = Date()
    for line in 1...UInt64(lineCount) {
        index.ensureLineIndexed(line, mappedFile: file)
    }
    let elapsed = Date().timeIntervalSince(start)

    #expect(index.lineCount == UInt64(lineCount))
    #expect(index.isComplete)
    #expect(elapsed < 5.0)
}
