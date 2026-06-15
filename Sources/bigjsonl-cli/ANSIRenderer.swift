import BigJSONLCore

/// Renders syntax-highlighted JSON tokens to a terminal using ANSI escape codes.
enum ANSIRenderer {

    /// ANSI color codes for each token type.
    /// Uses a common syntax-highlighting palette (similar to VS Code's Dark+).
    private static let colors: [TokenType: String] = [
        .punctuation:  "\u{001B}[38;5;59m",    // gray
        .key:          "\u{001B}[38;5;45m",    // cyan
        .stringValue:  "\u{001B}[38;5;208m",   // orange
        .number:       "\u{001B}[38;5;99m",    // purple
        .bool:         "\u{001B}[38;5;121m",   // green
        .null:         "\u{001B}[38;5;121m",   // green
        .invalid:      "\u{001B}[38;5;196m",   // red
    ]

    private static let reset = "\u{001B}[0m"

    /// Renders a line with ANSI syntax highlighting.
    ///
    /// - Parameters:
    ///   - lineText: The raw text of the line.
    ///   - tokens: The syntax tokens for the line.
    ///   - lineNumber: The 1-based line number to show in the gutter.
    ///   - noColor: If true, omit ANSI codes.
    /// - Returns: A string suitable for printing to a terminal.
    static func renderLine(
        lineText: String,
        tokens: [Token],
        lineNumber: UInt64,
        noColor: Bool = false
    ) -> String {
        let gutter = String(format: " %4d │ ", lineNumber)
        let body: String

        if noColor || tokens.isEmpty {
            body = lineText
        } else {
            body = renderColored(text: lineText, tokens: tokens)
        }

        return gutter + body
    }

    /// Apply colors to portions of the text based on tokens.
    private static func renderColored(text: String, tokens: [Token]) -> String {
        let utf8 = text.utf8
        var result = ""
        var lastEnd = 0

        for token in tokens {
            // Add any un-tokenized text between tokens
            let start = Int(token.range.lowerBound)
            if start > lastEnd {
                let rangeStart = utf8.index(utf8.startIndex, offsetBy: lastEnd)
                let rangeEnd = utf8.index(utf8.startIndex, offsetBy: start)
                result += String(text[rangeStart..<rangeEnd])
            }

            // Add the token with its color
            let tokenStart = utf8.index(utf8.startIndex, offsetBy: start)
            let tokenEnd = utf8.index(utf8.startIndex, offsetBy: Int(token.range.upperBound))
            let tokenStr = String(text[tokenStart..<tokenEnd])
            let color = colors[token.type] ?? ""
            result += "\(color)\(tokenStr)\(reset)"

            lastEnd = Int(token.range.upperBound)
        }

        // Add any remaining text after the last token
        if lastEnd < utf8.count {
            let rangeStart = utf8.index(utf8.startIndex, offsetBy: lastEnd)
            result += String(text[rangeStart...])
        }

        return result
    }

    /// Returns a help/status line rendered in a muted style.
    static func renderStatus(_ message: String) -> String {
        "\u{001B}[38;5;240m\(message)\(reset)"
    }

    /// Returns an error message in red.
    static func renderError(_ message: String) -> String {
        "\u{001B}[38;5;196m\(message)\(reset)"
    }
}
