/// A single match returned by a grep/ripgrep search.
public struct SearchResult: Equatable, Sendable {
    /// 1-based line number in the JSONL file.
    public let lineNumber: UInt64
    /// Byte offset of the matching line within the file.
    public let byteOffset: UInt64
    /// A bounded snippet of the matching line.
    public let lineText: String

    public init(lineNumber: UInt64, byteOffset: UInt64, lineText: String) {
        self.lineNumber = lineNumber
        self.byteOffset = byteOffset
        self.lineText = lineText
    }
}
