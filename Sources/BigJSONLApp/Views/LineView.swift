import SwiftUI
import BigJSONLCore

/// Renders a single JSONL line with syntax highlighting.
struct LineView: View {
    let lineInfo: LineInfo
    let isSelected: Bool

    /// Colors for each token type, matching the ANSI renderer's palette.
    private static let tokenColors: [TokenType: Color] = [
        .punctuation:  .secondary,
        .key:          .cyan,
        .stringValue:  .orange,
        .number:       .purple,
        .bool:         .green,
        .null:         .green,
        .invalid:      .red,
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Line number gutter
            lineNumberGutter

            // Line content with syntax highlighting
            highlightedContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .background(backgroundColor)
        .font(.system(.caption, design: .monospaced))
    }

    // MARK: - Line number gutter

    private var lineNumberGutter: some View {
        Text(String(format: "%5d", lineInfo.lineNumber))
            .foregroundStyle(.tertiary)
            .padding(.trailing, 8)
            .frame(minWidth: 48, alignment: .trailing)
            .background(.quaternary.opacity(0.3))
    }

    // MARK: - Syntax-highlighted content

    private var highlightedContent: some View {
        attributedLine
            .padding(.leading, 4)
            .padding(.vertical, 1)
    }

    private var attributedLine: Text {
        guard !lineInfo.tokens.isEmpty else {
            return Text(lineInfo.text)
        }

        var result = Text("")
        let utf8 = lineInfo.text.utf8
        var lastEnd = 0

        for token in lineInfo.tokens {
            let start = Int(token.range.lowerBound)
            let end = Int(token.range.upperBound)

            // Add un-tokenized text between tokens
            if start > lastEnd {
                let rangeStart = utf8.index(utf8.startIndex, offsetBy: lastEnd)
                let rangeEnd = utf8.index(utf8.startIndex, offsetBy: start)
                let segment = String(lineInfo.text[rangeStart..<rangeEnd])
                result = result + Text(segment)
            }

            // Add the token with its color
            if start < utf8.count {
                let rangeStart = utf8.index(utf8.startIndex, offsetBy: start)
                let rangeEnd = utf8.index(utf8.startIndex, offsetBy: min(end, utf8.count))
                let segment = String(lineInfo.text[rangeStart..<rangeEnd])
                let color = Self.tokenColors[token.type] ?? .primary
                result = result + Text(segment).foregroundColor(color)
            }

            lastEnd = end
        }

        // Add any remaining text after the last token
        if lastEnd < utf8.count {
            let rangeStart = utf8.index(utf8.startIndex, offsetBy: lastEnd)
            let segment = String(lineInfo.text[rangeStart...])
            result = result + Text(segment)
        }

        return result
    }

    // MARK: - Helpers

    private var backgroundColor: Color {
        if !lineInfo.isValidJSON {
            return .red.opacity(0.08)
        }
        if isSelected {
            return .accentColor.opacity(0.1)
        }
        return .clear
    }
}
