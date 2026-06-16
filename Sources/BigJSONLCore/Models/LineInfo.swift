/// Metadata about a parsed line in a JSONL file.
public struct LineInfo: Equatable, Sendable {
    /// 1-based line number in the file.
    public let lineNumber: UInt64
    /// Byte offset of this line within the file.
    public let byteOffset: UInt64
    /// Length of the line in bytes (including the newline character).
    public let byteLength: UInt64
    /// Whether the line was successfully parsed as JSON.
    public let isValidJSON: Bool
    /// Display text for this line (without the trailing newline).
    ///
    /// UI callers may store a bounded preview here to keep large viewport
    /// windows memory-efficient. Use `isTextTruncated` to distinguish previews
    /// from complete line text.
    public let text: String
    /// Whether `text` is a bounded preview rather than the full line.
    public let isTextTruncated: Bool
    /// Syntax tokens for this line, if parsing succeeded.
    public let tokens: [Token]

    public init(
        lineNumber: UInt64,
        byteOffset: UInt64,
        byteLength: UInt64,
        isValidJSON: Bool,
        text: String,
        isTextTruncated: Bool = false,
        tokens: [Token]
    ) {
        self.lineNumber = lineNumber
        self.byteOffset = byteOffset
        self.byteLength = byteLength
        self.isValidJSON = isValidJSON
        self.text = text
        self.isTextTruncated = isTextTruncated
        self.tokens = tokens
    }
}
