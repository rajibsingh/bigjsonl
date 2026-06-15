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
    var requestedScrollLine: UInt64?

    // MARK: - Search state
    var searchQuery: String = ""
    var searchResults: [SearchResult] = []
    var isSearching: Bool = false
    var searchError: String?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchGeneration = 0

    // MARK: - Inspector state
    var inspectorContent: JSONDisplayContent?
    var inspectorLineNumber: UInt64?
    var isPreparingInspector = false
    @ObservationIgnored private var inspectorTask: Task<Void, Never>?
    @ObservationIgnored private var inspectorCache: [UInt64: JSONDisplayContent] = [:]
    @ObservationIgnored private var inspectorCacheOrder: [UInt64] = []

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
            requestedScrollLine = line
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
        let endLine = safeCenter > UInt64.max - bufferSize
            ? UInt64.max
            : safeCenter + bufferSize

        // Index one line beyond the window so every displayed byte range has
        // either a known next-line boundary or a confirmed EOF.
        let lookaheadLine = endLine == UInt64.max ? endLine : endLine + 1
        index.ensureLineIndexed(lookaheadLine, mappedFile: file)
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

    var canLoadPreviousWindow: Bool {
        firstVisibleLine > 1
    }

    var canLoadNextWindow: Bool {
        guard let lastVisible = visibleLines.last?.lineNumber else { return false }
        return !index.isComplete || lastVisible < totalLines
    }

    /// Advances the bounded viewport while retaining an overlap for scroll anchoring.
    func loadNextWindow() {
        guard !isLoading, let lastVisible = visibleLines.last?.lineNumber else { return }
        let center = lastVisible > UInt64.max - bufferSize
            ? UInt64.max
            : lastVisible + bufferSize
        replaceWindow(around: center)
    }

    /// Moves the bounded viewport backward while retaining an overlap for scroll anchoring.
    func loadPreviousWindow() {
        guard !isLoading else { return }
        let center = firstVisibleLine > bufferSize
            ? firstVisibleLine - bufferSize
            : 1
        replaceWindow(around: center)
    }

    private func replaceWindow(around line: UInt64) {
        isLoading = true
        do {
            try loadWindow(around: line)
        } catch {
            errorMessage = "Error reading file: \(error.localizedDescription)"
        }
        isLoading = false
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

        let isValid = JSONTokenizer.isValid(displayText)

        return LineInfo(
            lineNumber: lineNum,
            byteOffset: offset,
            byteLength: length,
            isValidJSON: isValid,
            text: displayText,
            tokens: []
        )
    }

    // MARK: - Inspector

    func prepareInspector(for lineInfo: LineInfo) {
        inspectorTask?.cancel()
        inspectorLineNumber = lineInfo.lineNumber

        if let cached = inspectorCache[lineInfo.lineNumber] {
            inspectorContent = cached
            isPreparingInspector = false
            touchInspectorCache(lineInfo.lineNumber)
            return
        }

        inspectorContent = nil
        isPreparingInspector = true
        let lineNumber = lineInfo.lineNumber
        let text = lineInfo.text
        let isValid = lineInfo.isValidJSON

        inspectorTask = Task {
            let content = await Task.detached(priority: .userInitiated) {
                JSONFormatter.displayContent(text, isValid: isValid)
            }.value

            guard !Task.isCancelled, inspectorLineNumber == lineNumber else { return }
            cacheInspectorContent(content, for: lineNumber)
            inspectorContent = content
            isPreparingInspector = false
        }
    }

    private func cacheInspectorContent(_ content: JSONDisplayContent, for line: UInt64) {
        inspectorCache[line] = content
        touchInspectorCache(line)

        while inspectorCacheOrder.count > 3 {
            let evicted = inspectorCacheOrder.removeFirst()
            inspectorCache.removeValue(forKey: evicted)
        }
    }

    private func touchInspectorCache(_ line: UInt64) {
        inspectorCacheOrder.removeAll { $0 == line }
        inspectorCacheOrder.append(line)
    }

    // MARK: - Search

    /// Run a search using grep/rg.
    func performSearch() {
        guard !searchQuery.isEmpty, let _ = mappedFile else { return }

        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        searchError = nil
        let query = searchQuery

        searchTask = Task {
            defer {
                if generation == searchGeneration {
                    isSearching = false
                }
            }

            do {
                let results = try await Searcher.searchAsync(
                    pattern: query,
                    in: document.url,
                    limit: 500
                )
                try Task.checkCancellation()
                self.searchResults = results

                if let first = results.first {
                    scrollTo(line: first.lineNumber)
                }
            } catch is CancellationError {
                return
            } catch {
                searchError = "Search failed: \(error.localizedDescription)"
                self.searchResults = []
            }

        }
    }

    func cancelSearch() {
        searchGeneration += 1
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }

    func cancelInspectorPreparation() {
        inspectorTask?.cancel()
        inspectorTask = nil
        isPreparingInspector = false
    }
}
