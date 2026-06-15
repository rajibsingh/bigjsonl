/// The type of a syntax token within a JSONL line.
public enum TokenType: Equatable, Sendable {
    /// Structural punctuation: `{`, `}`, `[`, `]`, `,`, `:`
    case punctuation
    /// A JSON object key (the string to the left of `:`)
    case key
    /// A JSON string value
    case stringValue
    /// A JSON number literal
    case number
    /// A JSON boolean literal (`true` or `false`)
    case bool
    /// A JSON null literal
    case null
    /// An invalid/malformed line — entire line is one token of this type
    case invalid
}

/// A single syntax token within a line of a JSONL file.
///
/// `range` is expressed in bytes relative to the start of the line.
/// The token stream is ordered by ascending byte offset.
public struct Token: Equatable, Sendable {
    /// Byte range of this token within the line (0-based from line start).
    public let range: Range<UInt64>
    /// The semantic type of this token.
    public let type: TokenType

    public init(range: Range<UInt64>, type: TokenType) {
        self.range = range
        self.type = type
    }
}
