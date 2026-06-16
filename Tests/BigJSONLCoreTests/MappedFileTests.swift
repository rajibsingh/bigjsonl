import Testing
import Foundation
import BigJSONLCore

@Test("MappedFile opens existing file")
func mappedFileOpens() throws {
    let fixture = try TemporaryJSONLFile()
    let file = try MappedFile(url: fixture.url)
    #expect(file.size > 0)
    #expect(file.url == fixture.url)
}

@Test("MappedFile reads bytes from known offset")
func mappedFileReadsBytes() throws {
    let fixture = try TemporaryJSONLFile()
    let file = try MappedFile(url: fixture.url)

    // First byte should be '{'
    let firstByte = file.readByte(at: 0)
    #expect(firstByte == UInt8(ascii: "{"))

    // Read a range and verify
    let data = file.read(offset: 0, length: 10)
    #expect(data.count == 10)

    let firstTen = file.withUnsafeBytes(offset: 0, length: 10) { bytes in
        String(decoding: bytes, as: UTF8.self)
    }
    #expect(firstTen?.first == "{")
}

@Test("Mapped data retains its mapping owner")
func mappedDataRetainsOwner() throws {
    let fixture = try TemporaryJSONLFile()
    weak var weakFile: MappedFile?
    var data: DispatchData?

    do {
        let file = try MappedFile(url: fixture.url)
        weakFile = file
        data = file.read(offset: 0, length: file.size)
    }

    #expect(weakFile != nil)
    #expect(data?.count == Int(weakFile?.size ?? 0))
    data = nil
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
