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
    @ObservationIgnored private var viewportTask: Task<Void, Never>?
    @ObservationIgnored private var viewportGeneration = 0

    // MARK: - Search state
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
    @ObservationIgnored private var inspectorFormattingTask: Task<JSONDisplayContent, Error>?
    @ObservationIgnored private var inspectorCache: [UInt64: JSONDisplayContent] = [:]
    @ObservationIgnored private var inspectorCacheOrder: [UInt64] = []

    /// The number of lines to keep in the bounded viewport window.
    private var viewportLineCount: UInt64 = 41
    private let minimumViewportLineCount: UInt64 = 41
    private let viewportOverlap: UInt64 = 1
    private let estimatedLineRowHeight: CGFloat = 14
    private let viewportFillPadding: UInt64 = 8

    // MARK: - Initialization

    init(document: BigJSONLDocument) {
        self.document = document
        self.index = document.index
    }

    /// Open the file and load the initial viewport.
    func openFile() {
        guard mappedFile == nil else { return }
        cancelViewportLoad()
        isLoading = true
        errorMessage = nil

        do {
            let file = try MappedFile(url: document.url)
            self.mappedFile = file
            self.index = document.index

            // Load the initial window
            scheduleViewportLoad(startingAt: 1)
        } catch {
            errorMessage = "Failed to open file: \(error.localizedDescription)"
            isLoading = false
        }
    }

    // MARK: - Viewport management

    /// Load a window of lines around the given line number.
    func scrollTo(line: UInt64) {
        guard mappedFile != nil else { return }
        scheduleViewportLoad(
            startingAt: startLine(around: line),
            requestedScrollLine: line
        )
    }

    /// Resize the bounded line window so the loaded rows fill the visible pane.
    func updateViewportHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }

        let estimatedRows = UInt64((height / estimatedLineRowHeight).rounded(.up))
        let desiredCount = max(
            minimumViewportLineCount,
            estimatedRows + viewportFillPadding
        )

        guard desiredCount != viewportLineCount else { return }
        viewportLineCount = desiredCount

        guard mappedFile != nil, !visibleLines.isEmpty else { return }
        scheduleViewportLoad(startingAt: firstVisibleLine)
    }

    private func startLine(around centerLine: UInt64) -> UInt64 {
        let safeCenter = max(centerLine, 1)
        let halfWindow = viewportLineCount / 2
        return safeCenter > halfWindow ? safeCenter - halfWindow : 1
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
        let startLine = lastVisible > viewportOverlap
            ? lastVisible - viewportOverlap + 1
            : 1
        scheduleViewportLoad(startingAt: startLine)
    }

    /// Moves the bounded viewport backward while retaining an overlap for scroll anchoring.
    func loadPreviousWindow() {
        guard !isLoading else { return }
        let step = viewportLineCount > viewportOverlap
            ? viewportLineCount - viewportOverlap
            : 1
        let startLine = firstVisibleLine > step
            ? firstVisibleLine - step
            : 1
        scheduleViewportLoad(startingAt: startLine)
    }

    private func scheduleViewportLoad(
        startingAt line: UInt64,
        requestedScrollLine: UInt64? = nil
    ) {
        guard let file = mappedFile else { return }
        viewportTask?.cancel()
        viewportGeneration += 1
        let generation = viewportGeneration
        let indexSnapshot = index
        let count = viewportLineCount
        isLoading = true

        viewportTask = Task {
            do {
                let viewport = try await Task.detached(priority: .userInitiated) {
                    try ViewportLoader.load(
                        startingAt: line,
                        count: count,
                        mappedFile: file,
                        index: indexSnapshot
                    )
                }.value

                guard generation == viewportGeneration else { return }
                index = viewport.index
                totalLines = viewport.totalLines
                visibleLines = viewport.lines
                firstVisibleLine = viewport.firstVisibleLine
                if let requestedScrollLine {
                    self.requestedScrollLine = requestedScrollLine
                }
                isLoading = false
            } catch is CancellationError {
                if generation == viewportGeneration {
                    isLoading = false
                }
            } catch {
                if generation == viewportGeneration {
                    errorMessage = "Error reading file: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    private func cancelViewportLoad() {
        viewportGeneration += 1
        viewportTask?.cancel()
        viewportTask = nil
        isLoading = false
    }

    // MARK: - Inspector

    func prepareInspector(for lineInfo: LineInfo) {
        cancelInspectorPreparation()
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
        let formattingTask = Task.detached(priority: .userInitiated) {
            try JSONFormatter.displayContentCancellable(text, isValid: isValid)
        }
        inspectorFormattingTask = formattingTask

        inspectorTask = Task {
            do {
                let content = try await formattingTask.value

                guard !Task.isCancelled, inspectorLineNumber == lineNumber else { return }
                cacheInspectorContent(content, for: lineNumber)
                inspectorContent = content
                isPreparingInspector = false
                inspectorFormattingTask = nil
            } catch is CancellationError {
                if inspectorLineNumber == lineNumber {
                    isPreparingInspector = false
                }
            } catch {
                if inspectorLineNumber == lineNumber {
                    inspectorContent = JSONFormatter.displayContent(text, isValid: false)
                    isPreparingInspector = false
                }
            }
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
    func performSearch(query: String) {
        guard !query.isEmpty, let _ = mappedFile else { return }

        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        searchError = nil

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

    func clearSearch() {
        cancelSearch()
        searchResults = []
        searchError = nil
    }

    func cancelInspectorPreparation() {
        inspectorTask?.cancel()
        inspectorFormattingTask?.cancel()
        inspectorTask = nil
        inspectorFormattingTask = nil
        isPreparingInspector = false
    }

    func dispose() {
        cancelViewportLoad()
        cancelSearch()
        cancelInspectorPreparation()
        mappedFile = nil
        visibleLines = []
        searchResults = []
        inspectorContent = nil
        inspectorCache.removeAll()
        inspectorCacheOrder.removeAll()
    }
}

private struct LoadedViewport: Sendable {
    let index: LineOffsetIndex
    let totalLines: UInt64
    let firstVisibleLine: UInt64
    let lines: [LineInfo]
}

private enum ViewportLoader {
    static func load(
        startingAt requestedStartLine: UInt64,
        count: UInt64,
        mappedFile: MappedFile,
        index: LineOffsetIndex
    ) throws -> LoadedViewport {
        var index = index
        let requestedStartLine = max(requestedStartLine, 1)
        let requestedEndLine = requestedStartLine > UInt64.max - (count - 1)
            ? UInt64.max
            : requestedStartLine + count - 1

        let lookaheadLine = requestedEndLine == UInt64.max
            ? requestedEndLine
            : requestedEndLine + 1
        index.ensureLineIndexed(lookaheadLine, mappedFile: mappedFile)
        try Task.checkCancellation()

        let totalLines = index.lineCount
        guard totalLines > 0 else {
            return LoadedViewport(
                index: index,
                totalLines: 0,
                firstVisibleLine: 1,
                lines: []
            )
        }

        let startLine = min(requestedStartLine, totalLines)
        let endLine = startLine > UInt64.max - (count - 1)
            ? UInt64.max
            : startLine + count - 1

        var lines: [LineInfo] = []
        lines.reserveCapacity(Int(min(count, 512)))
        for lineNum in startLine...min(endLine, totalLines) {
            try Task.checkCancellation()
            guard let lineInfo = readLine(lineNum, file: mappedFile, index: index) else { continue }
            lines.append(lineInfo)
        }

        return LoadedViewport(
            index: index,
            totalLines: totalLines,
            firstVisibleLine: startLine,
            lines: lines
        )
    }

    private static func readLine(
        _ lineNum: UInt64,
        file: MappedFile,
        index: LineOffsetIndex
    ) -> LineInfo? {
        guard let offset = index.offsetForLine(lineNum) else { return nil }
        guard let range = index.byteRangeForLine(lineNum, fileSize: file.size) else { return nil }

        let length = range.upperBound - range.lowerBound
        let data = file.read(offset: offset, length: length)
        let rawData = Data(data)

        guard let text = String(data: rawData, encoding: .utf8) else { return nil }
        let displayText = text.trimmingCharacters(in: ["\n", "\r"])

        return LineInfo(
            lineNumber: lineNum,
            byteOffset: offset,
            byteLength: length,
            isValidJSON: JSONTokenizer.isValid(displayText),
            text: displayText,
            tokens: []
        )
    }
}
