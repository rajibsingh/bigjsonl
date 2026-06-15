import SwiftUI
import BigJSONLCore
import Observation

/// The central view model for the SwiftUI app.
///
/// Manages the file handle, index, visible line buffer, and search state.
/// Uses `@Observable` (macOS 15) for SwiftUI data flow.
@MainActor
@Observable
final class DocumentViewModel {
    // MARK: - File state
    let document: BigJSONLDocument
    private var mappedFile: MappedFile?
    private var index: LineOffsetIndex

    // MARK: - Viewport state
    var firstVisibleLine: UInt64 = 1
    var visibleLines: [LineInfo] = []
    var totalLines: UInt64 = 0
    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - Search state
    var searchQuery: String = ""
    var searchResults: [SearchResult] = []
    var isSearching: Bool = false
    var searchError: String?

    /// The number of lines to keep in the viewport buffer (above and below the visible area).
    private let bufferSize: UInt64 = 20

    // MARK: - Initialization

    init(document: BigJSONLDocument) {
        self.document = document
        self.index = document.index
    }

    /// Open the file and load the initial viewport.
    func openFile() {
        isLoading = true
        errorMessage = nil

        do {
            let file = try MappedFile(url: document.url)
            self.mappedFile = file
            self.index = document.index

            // Load the initial window
            try loadWindow(around: 1)
        } catch {
            errorMessage = "Failed to open file: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Viewport management

    /// Load a window of lines around the given line number.
    func scrollTo(line: UInt64) {
        guard mappedFile != nil else { return }
        isLoading = true

        do {
            try loadWindow(around: line)
        } catch {
            errorMessage = "Error reading file: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Load the viewport buffer around a center line.
    private func loadWindow(around centerLine: UInt64) throws {
        guard let file = mappedFile else { return }

        let safeCenter = max(centerLine, 1)
        let startLine = safeCenter > bufferSize ? safeCenter - bufferSize : 1
        let endLine = safeCenter + bufferSize

        // Ensure the index covers our window
        index.ensureLineIndexed(endLine, mappedFile: file)
        self.totalLines = index.lineCount

        // Read and tokenize each line in the window
        var lines: [LineInfo] = []
        for lineNum in startLine...min(endLine, totalLines) {
            guard let lineInfo = try readLine(lineNum, file: file) else { continue }
            lines.append(lineInfo)
        }

        self.visibleLines = lines
        self.firstVisibleLine = startLine
    }

    /// Read and tokenize a single line.
    private func readLine(_ lineNum: UInt64, file: MappedFile) throws -> LineInfo? {
        guard let offset = index.offsetForLine(lineNum) else { return nil }
        guard let range = index.byteRangeForLine(lineNum, fileSize: file.size) else { return nil }

        let length = range.upperBound - range.lowerBound
        let data = file.read(offset: offset, length: length)
        let rawData = Data(data)

        guard let text = String(data: rawData, encoding: .utf8) else { return nil }
        let displayText = text.trimmingCharacters(in: ["\n", "\r"])

        let (isValid, tokens) = JSONTokenizer.tokenize(displayText)

        return LineInfo(
            lineNumber: lineNum,
            byteOffset: offset,
            byteLength: length,
            isValidJSON: isValid,
            text: displayText,
            tokens: tokens
        )
    }

    // MARK: - Search

    /// Run a search using grep/rg.
    func performSearch() {
        guard !searchQuery.isEmpty, let _ = mappedFile else { return }

        isSearching = true
        searchError = nil

        do {
            let results = try Searcher.search(pattern: searchQuery, in: document.url)
            self.searchResults = results

            if let first = results.first {
                scrollTo(line: first.lineNumber)
            }
        } catch {
            searchError = "Search failed: \(error.localizedDescription)"
            self.searchResults = []
        }

        isSearching = false
    }
}
