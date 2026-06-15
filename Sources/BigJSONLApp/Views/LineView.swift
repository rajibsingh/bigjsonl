import SwiftUI
import BigJSONLCore

/// Renders a single JSONL line with syntax highlighting.
struct LineView: View {
    let lineInfo: LineInfo
    let isSelected: Bool

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
        SyntaxHighlightedText(
            text: lineInfo.text,
            tokens: lineInfo.tokens
        )
            .lineLimit(3)
            .truncationMode(.tail)
            .padding(.leading, 4)
            .padding(.vertical, 1)
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

/// Renders byte-ranged JSON tokens with the shared app syntax palette.
struct SyntaxHighlightedText: View {
    let text: String
    let tokens: [Token]

    private static let tokenColors: [TokenType: Color] = [
        .punctuation: .secondary,
        .key: .cyan,
        .stringValue: .orange,
        .number: .purple,
        .bool: .green,
        .null: .green,
        .invalid: .red,
    ]

    var body: some View {
        attributedText
    }

    private var attributedText: Text {
        guard !tokens.isEmpty else {
            return Text(text)
        }

        var result = Text("")
        let utf8 = text.utf8
        var lastEnd = 0

        for token in tokens {
            let start = min(Int(token.range.lowerBound), utf8.count)
            let end = min(Int(token.range.upperBound), utf8.count)

            if start > lastEnd {
                let rangeStart = utf8.index(utf8.startIndex, offsetBy: lastEnd)
                let rangeEnd = utf8.index(utf8.startIndex, offsetBy: start)
                result = result + Text(String(text[rangeStart..<rangeEnd]))
            }

            if start < end {
                let rangeStart = utf8.index(utf8.startIndex, offsetBy: start)
                let rangeEnd = utf8.index(utf8.startIndex, offsetBy: end)
                let color = Self.tokenColors[token.type] ?? .primary
                result = result + Text(String(text[rangeStart..<rangeEnd]))
                    .foregroundColor(color)
            }

            lastEnd = max(lastEnd, end)
        }

        if lastEnd < utf8.count {
            let rangeStart = utf8.index(utf8.startIndex, offsetBy: lastEnd)
            result = result + Text(String(text[rangeStart...]))
        }

        return result
    }
}
