import Testing
import Foundation
import BigJSONLCore

@Test("MappedFile opens existing file")
func mappedFileOpens() throws {
    let url = try testJSONLFile()
    let file = try MappedFile(url: url)
    #expect(file.size > 0)
    #expect(file.url == url)
}

@Test("MappedFile reads bytes from known offset")
func mappedFileReadsBytes() throws {
    let url = try testJSONLFile()
    let file = try MappedFile(url: url)

    // First byte should be '{'
    let firstByte = file.readByte(at: 0)
    #expect(firstByte == UInt8(ascii: "{"))

    // Read a range and verify
    let data = file.read(offset: 0, length: 10)
    #expect(data.count == 10)
}

@Test("MappedFile throws on nonexistent file")
func mappedFileThrows() {
    let url = URL(fileURLWithPath: "/nonexistent/path.jsonl")
    #expect(throws: MappedFileError.self) {
        try MappedFile(url: url)
    }
}

@Test("MappedFile handles empty file")
func mappedFileEmpty() throws {
    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID().uuidString).jsonl")
    FileManager.default.createFile(atPath: tmpURL.path, contents: Data())
    defer { try? FileManager.default.removeItem(at: tmpURL) }

    let file = try MappedFile(url: tmpURL)
    #expect(file.size == 0)
    #expect(file.readByte(at: 0) == nil)
}
