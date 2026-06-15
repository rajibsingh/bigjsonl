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
        Text(lineInfo.text)
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
