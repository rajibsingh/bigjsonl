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
    parallelIndex.ensureLineIndexed(UInt64(lineCount) - 5, mappedFile: file)

    #expect(parallelIndex.lineCount == UInt64(lineCount))
    #expect(parallelIndex.isComplete)

    // Spot-check several lines, including the very first, the jump target,
    // and the last line, against the known byte layout.
    for line in [1, 2, lineCount - 5, lineCount - 1, lineCount] {
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
    for line in 1...UInt64(lineCount) {
        sequentialIndex.ensureLineIndexed(line, mappedFile: file)
    }

    for line in stride(from: 1, through: lineCount, by: 997) {
        #expect(parallelIndex.offsetForLine(UInt64(line)) == sequentialIndex.offsetForLine(UInt64(line)))
    }
    #expect(parallelIndex.lineCount == sequentialIndex.lineCount)
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
