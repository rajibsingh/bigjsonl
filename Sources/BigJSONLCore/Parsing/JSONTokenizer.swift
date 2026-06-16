import JSON

/// A lightweight tokenizer that produces syntax tokens from a JSON string.
///
/// The tokenizer works in two phases:
/// 1. Parse the line with `swift-json` to validate it's well-formed JSON.
/// 2. Scan the raw UTF-8 bytes to produce byte-accurate `[Token]` entries.
///
/// Using swift-json purely for validation and a separate byte scan for token
/// positions gives us accurate source ranges, which swift-json's AST doesn't
/// preserve.
public enum JSONTokenizer {
    /// Returns whether the supplied text is valid JSON without producing tokens.
    public static func isValid(_ line: String) -> Bool {
        do {
            _ = try JSON.Node(parsing: line[...])
            return true
        } catch {
            return false
        }
    }

    /// Tokenizes a single line of JSON text.
    ///
    /// - Parameter line: The raw text of a JSONL line (without trailing newline).
    /// - Returns: A tuple with:
    ///   - `isValid`: Whether swift-json successfully parsed the line.
    ///   - `tokens`: The syntax tokens for the line. For invalid lines, a single
    ///     `.invalid` token spanning the entire line is returned.
    public static func tokenize(_ line: String) -> (isValid: Bool, tokens: [Token]) {
        // Phase 1: Validate with swift-json
        let isValid = isValid(line)

        guard isValid else {
            let length = UInt64(line.utf8.count)
            return (false, [Token(range: 0..<length, type: .invalid)])
        }

        return (true, tokenizeValidJSON(line))
    }

    static func tokenizeValidJSON(_ line: String) -> [Token] {
        // This non-throwing path is used by synchronous callers that already
        // validated the JSON and do not need cooperative cancellation.
        (try? tokenizeValidJSON(line, checkingCancellation: false)) ?? []
    }

    static func tokenizeValidJSON(
        _ line: String,
        checkingCancellation: Bool
    ) throws -> [Token] {
        // Phase 2: Byte-level tokenization
        let bytes = Array(line.utf8)
        var tokens: [Token] = []
        tokens.reserveCapacity(64)

        var pos = 0
        while pos < bytes.count {
            if checkingCancellation, pos.isMultiple(of: 4096) {
                try Task.checkCancellation()
            }

            let start = UInt64(pos)
            let byte = bytes[pos]

            switch byte {
            // Punctuation
            case UInt8(ascii: "{"), UInt8(ascii: "}"),
                 UInt8(ascii: "["), UInt8(ascii: "]"),
                 UInt8(ascii: ","), UInt8(ascii: ":"):
                pos += 1
                tokens.append(Token(range: start..<UInt64(pos), type: .punctuation))

            // String (key or value)
            case UInt8(ascii: "\""):
                pos += 1
                while pos < bytes.count {
                    if bytes[pos] == UInt8(ascii: "\\") {
                        pos += 2 // skip escape sequence (e.g., \", \\, \n)
                    } else if bytes[pos] == UInt8(ascii: "\"") {
                        pos += 1 // closing quote
                        break
                    } else {
                        pos += 1
                    }
                }
                let type: TokenType = isFollowedByColon(at: pos, in: bytes) ? .key : .stringValue
                tokens.append(Token(range: start..<UInt64(pos), type: type))

            // Boolean: true / false
            case UInt8(ascii: "t"):
                if bytes[pos...].starts(with: "true".utf8) {
                    pos += 4
                    tokens.append(Token(range: start..<UInt64(pos), type: .bool))
                } else {
                    pos += 1
                }

            case UInt8(ascii: "f"):
                if bytes[pos...].starts(with: "false".utf8) {
                    pos += 5
                    tokens.append(Token(range: start..<UInt64(pos), type: .bool))
                } else {
                    pos += 1
                }

            // Null: null
            case UInt8(ascii: "n"):
                if bytes[pos...].starts(with: "null".utf8) {
                    pos += 4
                    tokens.append(Token(range: start..<UInt64(pos), type: .null))
                } else {
                    pos += 1
                }

            // Number: -?[0-9]... including scientific notation and decimals
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
                pos += 1
                while pos < bytes.count {
                    let c = bytes[pos]
                    let isDigit = c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9")
                    let isNumberChar = isDigit
                        || c == UInt8(ascii: ".")
                        || c == UInt8(ascii: "-")
                        || c == UInt8(ascii: "+")
                        || c == UInt8(ascii: "e")
                        || c == UInt8(ascii: "E")
                    if isNumberChar {
                        pos += 1
                    } else {
                        break
                    }
                }
                tokens.append(Token(range: start..<UInt64(pos), type: .number))

            // Whitespace and everything else — skip
            default:
                pos += 1
            }
        }

        return tokens
    }

    /// Checks whether the byte position is followed by `:` (ignoring whitespace),
    /// indicating the preceding string is a JSON object key.
    private static func isFollowedByColon(at pos: Int, in bytes: [UInt8]) -> Bool {
        var p = pos
        while p < bytes.count {
            let b = bytes[p]
            if b == UInt8(ascii: ":") {
                return true
            }
            // Skip whitespace only
            if b != UInt8(ascii: " ") && b != UInt8(ascii: "\t") {
                return false
            }
            p += 1
        }
        return false
    }
}
