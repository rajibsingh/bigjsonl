import Testing
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
