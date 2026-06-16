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
    var inspectorLineInfo: LineInfo?
    var inspectorLineNumber: UInt64?
    var isPreparingInspector = false
    @ObservationIgnored private var inspectorTask: Task<Void, Never>?
    @ObservationIgnored private var inspectorFormattingTask: Task<JSONDisplayContent, Error>?
    @ObservationIgnored private var inspectorCache: [UInt64: JSONDisplayContent] = [:]
    @ObservationIgnored private var inspectorCacheOrder: [UInt64] = []

    /// The number of lines to keep in the bounded viewport window.
    private var viewportLineCount: UInt64 = 123
    private let minimumVisibleLineCount: UInt64 = 41
    private let viewportOverscanMultiplier: UInt64 = 3
    private let estimatedLineRowHeight: CGFloat = 14
    private let viewportFillPadding: UInt64 = 8
    private let maximumInspectorCacheEntries = 1

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
            minimumVisibleLineCount,
            estimatedRows + viewportFillPadding
        ) * viewportOverscanMultiplier

        guard desiredCount != viewportLineCount else { return }
        viewportLineCount = desiredCount

        guard mappedFile != nil, !visibleLines.isEmpty else { return }
        scheduleViewportLoad(startingAt: firstVisibleLine)
    }

    var loadedLineCount: UInt64 {
        viewportLineCount
    }

    var visiblePaneLineEstimate: UInt64 {
        max(
            minimumVisibleLineCount,
            viewportLineCount / viewportOverscanMultiplier
        )
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

    /// Advances the bounded viewport while retaining buffered rows for scroll anchoring.
    func loadNextWindow(preserving anchorLine: UInt64? = nil) {
        guard !isLoading, canLoadNextWindow,
              let lastVisible = visibleLines.last?.lineNumber else { return }
        let step = max(visiblePaneLineEstimate, 1)
        let requestedStart = firstVisibleLine > UInt64.max - step
            ? UInt64.max
            : firstVisibleLine + step
        let startLine = min(requestedStart, lastVisible)
        scheduleViewportLoad(startingAt: startLine, requestedScrollLine: anchorLine)
    }

    /// Moves the bounded viewport backward while retaining buffered rows for scroll anchoring.
    func loadPreviousWindow(preserving anchorLine: UInt64? = nil) {
        guard !isLoading, canLoadPreviousWindow else { return }
        let step = max(visiblePaneLineEstimate, 1)
        let startLine = firstVisibleLine > step
            ? firstVisibleLine - step
            : 1
        scheduleViewportLoad(startingAt: startLine, requestedScrollLine: anchorLine)
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
                    try await ViewportLoader.load(
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
        inspectorLineInfo = lineInfo
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
        let isValid = lineInfo.isValidJSON
        let file = mappedFile
        let indexSnapshot = index
        let formattingTask = Task.detached(priority: .userInitiated) {
            let text = try ViewportLoader.fullText(
                for: lineNumber,
                file: file,
                index: indexSnapshot
            )
            return try JSONFormatter.displayContentCancellable(text, isValid: isValid)
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
                    inspectorContent = JSONFormatter.displayContent(lineInfo.text, isValid: false)
                    isPreparingInspector = false
                }
            }
        }
    }

    private func cacheInspectorContent(_ content: JSONDisplayContent, for line: UInt64) {
        inspectorCache[line] = content
        touchInspectorCache(line)

        while inspectorCacheOrder.count > maximumInspectorCacheEntries {
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

    func releaseInspectorDisplayState() {
        cancelInspectorPreparation()
        inspectorLineInfo = nil
        inspectorLineNumber = nil
        inspectorContent = nil
        inspectorCache.removeAll()
        inspectorCacheOrder.removeAll()
    }

    func dispose() {
        cancelViewportLoad()
        cancelSearch()
        releaseInspectorDisplayState()
        mappedFile = nil
        visibleLines = []
        searchResults = []
    }
}

private struct LoadedViewport: Sendable {
    let index: LineOffsetIndex
    let totalLines: UInt64
    let firstVisibleLine: UInt64
    let lines: [LineInfo]
}

private enum ViewportLoader {
    private static let maximumPreviewCharacters = 6_000

    static func load(
        startingAt requestedStartLine: UInt64,
        count: UInt64,
        mappedFile: MappedFile,
        index: LineOffsetIndex
    ) async throws -> LoadedViewport {
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
        let endLine = min(
            startLine > UInt64.max - (count - 1) ? UInt64.max : startLine + count - 1,
            totalLines
        )

        let lines = try await readLines(
            from: startLine,
            through: endLine,
            file: mappedFile,
            index: index
        )

        return LoadedViewport(
            index: index,
            totalLines: totalLines,
            firstVisibleLine: startLine,
            lines: lines
        )
    }

    /// Reads and validates a contiguous range of lines, fanning the per-line
    /// work (mmap read, UTF-8 decode, JSON validity check) out across a
    /// `TaskGroup` since each line is independent and CPU-bound. Results are
    /// reassembled in line-number order before returning.
    private static func readLines(
        from startLine: UInt64,
        through endLine: UInt64,
        file: MappedFile,
        index: LineOffsetIndex
    ) async throws -> [LineInfo] {
        guard endLine >= startLine else { return [] }
        let totalCount = Int(endLine - startLine + 1)

        let chunkCount = min(
            max(ProcessInfo.processInfo.activeProcessorCount, 1),
            totalCount
        )
        let chunkSize = UInt64((totalCount + chunkCount - 1) / chunkCount)

        var chunks: [(start: UInt64, end: UInt64)] = []
        var chunkStart = startLine
        while chunkStart <= endLine {
            let chunkEnd = min(chunkStart + chunkSize - 1, endLine)
            chunks.append((chunkStart, chunkEnd))
            chunkStart = chunkEnd + 1
        }

        var results = [(Int, [LineInfo])](repeating: (0, []), count: chunks.count)
        try await withThrowingTaskGroup(of: (Int, [LineInfo]).self) { group in
            for (chunkIndex, chunk) in chunks.enumerated() {
                group.addTask {
                    var chunkLines: [LineInfo] = []
                    chunkLines.reserveCapacity(Int(chunk.end - chunk.start + 1))
                    for lineNum in chunk.start...chunk.end {
                        try Task.checkCancellation()
                        guard let lineInfo = readLine(lineNum, file: file, index: index) else { continue }
                        chunkLines.append(lineInfo)
                    }
                    return (chunkIndex, chunkLines)
                }
            }
            for try await (chunkIndex, chunkLines) in group {
                results[chunkIndex] = (chunkIndex, chunkLines)
            }
        }

        return results.flatMap { $0.1 }
    }

    private static func readLine(
        _ lineNum: UInt64,
        file: MappedFile,
        index: LineOffsetIndex
    ) -> LineInfo? {
        guard let offset = index.offsetForLine(lineNum) else { return nil }
        guard let range = index.byteRangeForLine(lineNum, fileSize: file.size) else { return nil }

        let length = range.upperBound - range.lowerBound
        let text: String? = length == 0
            ? ""
            : file.withUnsafeBytes(offset: offset, length: length) { String(bytes: $0, encoding: .utf8) } ?? nil
        guard let text else { return nil }
        let fullText = text.trimmingCharacters(in: ["\n", "\r"])
        let preview = previewText(for: fullText)

        return LineInfo(
            lineNumber: lineNum,
            byteOffset: offset,
            byteLength: length,
            isValidJSON: JSONTokenizer.isValid(fullText),
            text: preview.text,
            isTextTruncated: preview.isTruncated,
            tokens: []
        )
    }

    static func fullText(
        for lineNum: UInt64,
        file: MappedFile?,
        index: LineOffsetIndex
    ) throws -> String {
        guard let file,
              let offset = index.offsetForLine(lineNum),
              let range = index.byteRangeForLine(lineNum, fileSize: file.size) else {
            throw CancellationError()
        }

        let length = range.upperBound - range.lowerBound
        let text: String? = length == 0
            ? ""
            : file.withUnsafeBytes(offset: offset, length: length) { String(bytes: $0, encoding: .utf8) } ?? nil
        guard let text else {
            return "<invalid UTF-8>"
        }
        return text.trimmingCharacters(in: ["\n", "\r"])
    }

    private static func previewText(for text: String) -> (text: String, isTruncated: Bool) {
        guard text.count > maximumPreviewCharacters else {
            return (text, false)
        }

        let end = text.index(text.startIndex, offsetBy: maximumPreviewCharacters)
        return (String(text[..<end]) + "...", true)
    }
}
