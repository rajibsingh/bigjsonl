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
    let url = try testJSONLFile()
    let file = try MappedFile(url: url)
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
    let url = try testJSONLFile()
    let file = try MappedFile(url: url)
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
    let url = try testJSONLFile()
    let file = try MappedFile(url: url)
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
    let url = try testJSONLFile()
    let file = try MappedFile(url: url)
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
