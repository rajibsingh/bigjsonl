import Foundation
import Testing
@testable import BigJSONLApp

@MainActor
@Test("Viewport advances and retreats with bounded overscan windows")
func viewportNavigation() async throws {
    let fixture = try AppTestJSONLFile(lineCount: 300)
    let viewModel = DocumentViewModel(
        document: BigJSONLDocument(url: fixture.url)
    )

    viewModel.openFile()
    try await waitForLoading(viewModel)
    #expect(viewModel.visibleLines.first?.lineNumber == 1)
    #expect(viewModel.visibleLines.last?.lineNumber == viewModel.loadedLineCount)
    #expect(viewModel.visibleLines.allSatisfy { $0.tokens.isEmpty })
    #expect(viewModel.canLoadNextWindow)

    viewModel.loadNextWindow()
    try await waitForLoading(viewModel)
    #expect(viewModel.visibleLines.first?.lineNumber == viewModel.visiblePaneLineEstimate + 1)
    #expect(viewModel.visibleLines.last?.lineNumber == viewModel.visiblePaneLineEstimate + viewModel.loadedLineCount)
    #expect(viewModel.visibleLines.last?.text == "{\"line\":\(viewModel.visiblePaneLineEstimate + viewModel.loadedLineCount),\"value\":\"match\"}")

    viewModel.loadPreviousWindow()
    try await waitForLoading(viewModel)
    #expect(viewModel.visibleLines.first?.lineNumber == 1)
    #expect(viewModel.visibleLines.last?.lineNumber == viewModel.loadedLineCount)
}

@MainActor
@Test("Viewport keeps buffered rows before and after the visible pane")
func viewportKeepsOverscanBuffer() async throws {
    let fixture = try AppTestJSONLFile(lineCount: 500)
    let viewModel = DocumentViewModel(
        document: BigJSONLDocument(url: fixture.url)
    )

    viewModel.openFile()
    try await waitForLoading(viewModel)

    #expect(viewModel.loadedLineCount >= viewModel.visiblePaneLineEstimate * 3)

    viewModel.loadNextWindow()
    try await waitForLoading(viewModel)

    let firstLine = try #require(viewModel.visibleLines.first?.lineNumber)
    let lastLine = try #require(viewModel.visibleLines.last?.lineNumber)
    #expect(firstLine == viewModel.visiblePaneLineEstimate + 1)
    #expect(lastLine - firstLine + 1 == viewModel.loadedLineCount)
}

@MainActor
@Test("Extra bottom loads at EOF keep the final viewport stable")
func repeatedBottomLoadAtEOFIsNoOp() async throws {
    let fixture = try AppTestJSONLFile(lineCount: 100)
    let viewModel = DocumentViewModel(
        document: BigJSONLDocument(url: fixture.url)
    )

    viewModel.openFile()
    try await waitForLoading(viewModel)

    while viewModel.canLoadNextWindow {
        viewModel.loadNextWindow()
        try await waitForLoading(viewModel)
    }

    let firstAtEOF = viewModel.visibleLines.first?.lineNumber
    let lastAtEOF = viewModel.visibleLines.last?.lineNumber
    #expect(lastAtEOF == 100)

    viewModel.loadNextWindow()
    try await waitForLoading(viewModel)

    #expect(viewModel.visibleLines.first?.lineNumber == firstAtEOF)
    #expect(viewModel.visibleLines.last?.lineNumber == lastAtEOF)
}

@MainActor
@Test("Viewport grows to fill a taller line pane")
func viewportGrowsToFillTallerPane() async throws {
    let fixture = try AppTestJSONLFile(lineCount: 200)
    let viewModel = DocumentViewModel(
        document: BigJSONLDocument(url: fixture.url)
    )

    viewModel.openFile()
    try await waitForLoading(viewModel)
    viewModel.updateViewportHeight(1_000)
    try await waitForLoading(viewModel)

    #expect(viewModel.visibleLines.first?.lineNumber == 1)
    #expect(viewModel.visibleLines.last?.lineNumber == 200)
    #expect(!viewModel.canLoadNextWindow)
}

@MainActor
@Test("Viewport rows keep bounded previews while inspector loads full content")
func viewportRowsUseBoundedPreviews() async throws {
    let payload = String(repeating: "x", count: 20_000)
    let fixture = try AppTestJSONLFile(contents: #"{"payload":"\#(payload)"}"#)
    let viewModel = DocumentViewModel(
        document: BigJSONLDocument(url: fixture.url)
    )

    viewModel.openFile()
    try await waitForLoading(viewModel)

    let line = try #require(viewModel.visibleLines.first)
    #expect(line.isTextTruncated)
    #expect(line.text.count < 7_000)

    viewModel.prepareInspector(for: line)
    for _ in 0..<200 where viewModel.isPreparingInspector {
        try await Task.sleep(for: .milliseconds(5))
    }

    let content = try #require(viewModel.inspectorContent)
    #expect(content.text.contains(payload))

    viewModel.releaseInspectorDisplayState()
    #expect(viewModel.inspectorContent == nil)
    #expect(viewModel.inspectorLineInfo == nil)
    #expect(viewModel.inspectorLineNumber == nil)
}

@MainActor
@Test("Inspector content prepares asynchronously and reuses its cache")
func inspectorPreparationIsCached() async throws {
    let fixture = try AppTestJSONLFile(lineCount: 2)
    let viewModel = DocumentViewModel(
        document: BigJSONLDocument(url: fixture.url)
    )
    viewModel.openFile()
    try await waitForLoading(viewModel)
    let line = try #require(viewModel.visibleLines.first)

    viewModel.prepareInspector(for: line)
    #expect(viewModel.inspectorLineNumber == line.lineNumber)

    for _ in 0..<200 where viewModel.isPreparingInspector {
        try await Task.sleep(for: .milliseconds(5))
    }

    let prepared = try #require(viewModel.inspectorContent)
    #expect(prepared.text.contains("\n"))
    #expect(!prepared.tokens.isEmpty)

    viewModel.prepareInspector(for: line)
    #expect(!viewModel.isPreparingInspector)
    #expect(viewModel.inspectorContent == prepared)
}

@MainActor
@Test("Inspector content can be prepared again after tab state is released")
func inspectorPreparationRecoversAfterRelease() async throws {
    let fixture = try AppTestJSONLFile(lineCount: 2)
    let viewModel = DocumentViewModel(
        document: BigJSONLDocument(url: fixture.url)
    )
    viewModel.openFile()
    try await waitForLoading(viewModel)
    let line = try #require(viewModel.visibleLines.first)

    viewModel.prepareInspector(for: line)
    try await waitForInspectorPreparation(viewModel)
    let firstContent = try #require(viewModel.inspectorContent)

    viewModel.releaseInspectorDisplayState()
    #expect(viewModel.inspectorLineNumber == nil)
    #expect(viewModel.inspectorLineInfo == nil)
    #expect(viewModel.inspectorContent == nil)

    viewModel.prepareInspector(for: line)
    try await waitForInspectorPreparation(viewModel)

    #expect(viewModel.inspectorLineNumber == line.lineNumber)
    #expect(viewModel.inspectorLineInfo?.lineNumber == line.lineNumber)
    #expect(viewModel.inspectorContent == firstContent)
}

@MainActor
@Test("Inspector keeps selected line metadata after viewport moves away")
func inspectorMetadataSurvivesViewportMovement() async throws {
    let fixture = try AppTestJSONLFile(lineCount: 500)
    let viewModel = DocumentViewModel(
        document: BigJSONLDocument(url: fixture.url)
    )
    viewModel.openFile()
    try await waitForLoading(viewModel)
    let selectedLine = try #require(viewModel.visibleLines.first)

    viewModel.prepareInspector(for: selectedLine)
    try await waitForInspectorPreparation(viewModel)
    let selectedContent = try #require(viewModel.inspectorContent)

    while viewModel.visibleLines.contains(where: { $0.lineNumber == selectedLine.lineNumber }) {
        viewModel.loadNextWindow()
        try await waitForLoading(viewModel)
    }

    #expect(viewModel.inspectorLineNumber == selectedLine.lineNumber)
    #expect(viewModel.inspectorLineInfo?.lineNumber == selectedLine.lineNumber)
    #expect(viewModel.inspectorContent == selectedContent)
}

@MainActor
@Test("App search runs asynchronously and caps retained results")
func asynchronousSearchIsBounded() async throws {
    let fixture = try AppTestJSONLFile(lineCount: 1_000)
    let viewModel = DocumentViewModel(
        document: BigJSONLDocument(url: fixture.url)
    )
    viewModel.openFile()
    try await waitForLoading(viewModel)
    viewModel.performSearch(query: "match")
    #expect(viewModel.isSearching)

    for _ in 0..<200 where viewModel.isSearching {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(!viewModel.isSearching)
    #expect(viewModel.searchError == nil)
    #expect(viewModel.searchResults.count == 500)
}

@MainActor
@Test("Disposing the view model cancels work and clears retained content")
func disposingViewModelClearsState() async throws {
    let fixture = try AppTestJSONLFile(lineCount: 1_000)
    let viewModel = DocumentViewModel(
        document: BigJSONLDocument(url: fixture.url)
    )
    viewModel.openFile()
    try await waitForLoading(viewModel)

    viewModel.performSearch(query: "match")
    viewModel.dispose()

    #expect(!viewModel.isSearching)
    #expect(viewModel.visibleLines.isEmpty)
    #expect(viewModel.searchResults.isEmpty)
    #expect(viewModel.inspectorContent == nil)
    #expect(viewModel.inspectorLineInfo == nil)
}

@MainActor
private func waitForLoading(
    _ viewModel: DocumentViewModel
) async throws {
    for _ in 0..<200 where viewModel.isLoading {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(!viewModel.isLoading)
}

@MainActor
private func waitForInspectorPreparation(
    _ viewModel: DocumentViewModel
) async throws {
    for _ in 0..<200 where viewModel.isPreparingInspector {
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(!viewModel.isPreparingInspector)
}

private final class AppTestJSONLFile {
    let url: URL

    convenience init(lineCount: Int) throws {
        let contents = (1...lineCount)
            .map { "{\"line\":\($0),\"value\":\"match\"}" }
            .joined(separator: "\n")
        try self.init(contents: contents)
    }

    init(contents: String) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bigjsonl-app-test-\(UUID().uuidString).jsonl")
        try Data(contents.utf8).write(to: url)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
