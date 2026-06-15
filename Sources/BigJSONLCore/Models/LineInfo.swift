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
    /// The raw text of the line (without the trailing newline).
    public let text: String
    /// Syntax tokens for this line, if parsing succeeded.
    public let tokens: [Token]

    public init(
        lineNumber: UInt64,
        byteOffset: UInt64,
        byteLength: UInt64,
        isValidJSON: Bool,
        text: String,
        tokens: [Token]
    ) {
        self.lineNumber = lineNumber
        self.byteOffset = byteOffset
        self.byteLength = byteLength
        self.isValidJSON = isValidJSON
        self.text = text
        self.tokens = tokens
    }
}
