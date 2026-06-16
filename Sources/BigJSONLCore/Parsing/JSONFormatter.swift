/// Formatting utilities for presenting JSON without changing its values or key order.
public enum JSONFormatter {
    /// Prepares text and syntax tokens for a formatted content view.
    public static func displayContent(
        _ json: String,
        isValid: Bool
    ) -> JSONDisplayContent {
        guard isValid else {
            return JSONDisplayContent(
                text: json,
                tokens: [Token(range: 0..<UInt64(json.utf8.count), type: .invalid)]
            )
        }

        let text = prettyPrinted(json, indentation: 2, validate: false)
        return JSONDisplayContent(
            text: text,
            tokens: JSONTokenizer.tokenizeValidJSON(text)
        )
    }

    /// Prepares text and syntax tokens, checking cancellation during large records.
    public static func displayContentCancellable(
        _ json: String,
        isValid: Bool
    ) throws -> JSONDisplayContent {
        try Task.checkCancellation()
        guard isValid else {
            return JSONDisplayContent(
                text: json,
                tokens: [Token(range: 0..<UInt64(json.utf8.count), type: .invalid)]
            )
        }

        let text = try prettyPrinted(
            json,
            indentation: 2,
            validate: false,
            checkingCancellation: true
        )
        return JSONDisplayContent(
            text: text,
            tokens: try JSONTokenizer.tokenizeValidJSON(
                text,
                checkingCancellation: true
            )
        )
    }

    /// Pretty-prints valid JSON using the requested indentation width.
    ///
    /// Strings and number literals are preserved exactly. Invalid JSON is returned
    /// unchanged so callers can still display the original line.
    public static func prettyPrinted(_ json: String, indentation: Int = 2) -> String {
        prettyPrinted(json, indentation: indentation, validate: true)
    }

    private static func prettyPrinted(
        _ json: String,
        indentation: Int,
        validate: Bool
    ) -> String {
        (try? prettyPrinted(
            json,
            indentation: indentation,
            validate: validate,
            checkingCancellation: false
        )) ?? json
    }

    private static func prettyPrinted(
        _ json: String,
        indentation: Int,
        validate: Bool,
        checkingCancellation: Bool
    ) throws -> String {
        guard indentation >= 0,
              !validate || JSONTokenizer.isValid(json) else {
            return json
        }

        let bytes = Array(json.utf8)
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count + bytes.count / 4)

        var depth = 0
        var index = 0
        var isInString = false
        var isEscaped = false

        while index < bytes.count {
            if checkingCancellation, index.isMultiple(of: 4096) {
                try Task.checkCancellation()
            }

            let byte = bytes[index]

            if isInString {
                result.append(byte)
                if isEscaped {
                    isEscaped = false
                } else if byte == UInt8(ascii: "\\") {
                    isEscaped = true
                } else if byte == UInt8(ascii: "\"") {
                    isInString = false
                }
                index += 1
                continue
            }

            switch byte {
            case UInt8(ascii: "\""):
                isInString = true
                result.append(byte)
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                result.append(byte)
                if nextNonWhitespaceByte(after: index, in: bytes) != matchingClose(for: byte) {
                    depth += 1
                    appendNewline(to: &result, depth: depth, indentation: indentation)
                }
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                let openingByte = byte == UInt8(ascii: "}")
                    ? UInt8(ascii: "{")
                    : UInt8(ascii: "[")
                if result.last != openingByte {
                    depth = max(depth - 1, 0)
                    appendNewline(to: &result, depth: depth, indentation: indentation)
                }
                result.append(byte)
            case UInt8(ascii: ","):
                result.append(byte)
                appendNewline(to: &result, depth: depth, indentation: indentation)
            case UInt8(ascii: ":"):
                result.append(byte)
                result.append(UInt8(ascii: " "))
            case UInt8(ascii: " "), UInt8(ascii: "\t"),
                 UInt8(ascii: "\n"), UInt8(ascii: "\r"):
                break
            default:
                result.append(byte)
            }

            index += 1
        }

        return String(decoding: result, as: UTF8.self)
    }

    private static func nextNonWhitespaceByte(after index: Int, in bytes: [UInt8]) -> UInt8? {
        var next = index + 1
        while next < bytes.count {
            let byte = bytes[next]
            if byte != UInt8(ascii: " "),
               byte != UInt8(ascii: "\t"),
               byte != UInt8(ascii: "\n"),
               byte != UInt8(ascii: "\r") {
                return byte
            }
            next += 1
        }
        return nil
    }

    private static func matchingClose(for byte: UInt8) -> UInt8 {
        byte == UInt8(ascii: "{") ? UInt8(ascii: "}") : UInt8(ascii: "]")
    }

    private static func appendNewline(
        to result: inout [UInt8],
        depth: Int,
        indentation: Int
    ) {
        result.append(UInt8(ascii: "\n"))
        result.append(contentsOf: repeatElement(
            UInt8(ascii: " "),
            count: depth * indentation
        ))
    }
}

/// Prepared text and byte-ranged tokens for a JSON content view.
public struct JSONDisplayContent: Equatable, Sendable {
    public let text: String
    public let tokens: [Token]

    public init(text: String, tokens: [Token]) {
        self.text = text
        self.tokens = tokens
    }
}
