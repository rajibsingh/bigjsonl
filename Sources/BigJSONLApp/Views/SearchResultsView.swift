import SwiftUI
import BigJSONLCore

struct SearchResultsView: View {
    let results: [SearchResult]
    let query: String
    let selectedLine: UInt64?
    let onSelect: (SearchResult) -> Void

    var body: some View {
        List(results, id: \.lineNumber, selection: .constant(selectedLine)) { result in
            Button {
                onSelect(result)
            } label: {
                resultRow(result)
            }
            .buttonStyle(.plain)
            .listRowBackground(
                selectedLine == result.lineNumber
                    ? Color.accentColor.opacity(0.1)
                    : Color.clear
            )
        }
        .listStyle(.plain)
    }

    // MARK: - Row

    private func resultRow(_ result: SearchResult) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(String(format: "%5d", result.lineNumber))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 8)
                .frame(minWidth: 48, alignment: .trailing)
                .background(.quaternary.opacity(0.3))

            snippetText(for: result.lineText)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.tail)
                .padding(.leading, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    // MARK: - Snippet with highlighted match

    private func snippetText(for text: String) -> Text {
        guard !query.isEmpty,
              let range = text.range(of: query, options: [.caseInsensitive]) else {
            return Text(text)
                .foregroundStyle(.primary)
        }

        let before = Text(String(text[text.startIndex..<range.lowerBound]))
            .foregroundStyle(.primary)
        let match = Text(String(text[range]))
            .foregroundStyle(.orange)
            .bold()
        let after = Text(String(text[range.upperBound...]))
            .foregroundStyle(.primary)

        return before + match + after
    }
}
