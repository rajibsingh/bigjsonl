import Foundation
import Testing
@testable import BigJSONLApp

@MainActor
@Test("Viewport advances and retreats with bounded overlapping windows")
func viewportNavigation() throws {
    let fixture = try AppTestJSONLFile(lineCount: 100)
    let viewModel = DocumentViewModel(
        document: BigJSONLDocument(url: fixture.url)
    )

    viewModel.openFile()
    #expect(viewModel.visibleLines.first?.lineNumber == 1)
    #expect(viewModel.visibleLines.last?.lineNumber == 21)
    #expect(viewModel.visibleLines.allSatisfy { $0.tokens.isEmpty })
    #expect(viewModel.canLoadNextWindow)

    viewModel.loadNextWindow()
    #expect(viewModel.visibleLines.first?.lineNumber == 21)
    #expect(viewModel.visibleLines.last?.lineNumber == 61)
    #expect(viewModel.visibleLines.last?.text == "{\"line\":61,\"value\":\"match\"}")

    viewModel.loadPreviousWindow()
    #expect(viewModel.visibleLines.first?.lineNumber == 1)
    #expect(viewModel.visibleLines.last?.lineNumber == 21)
}

@MainActor
@Test("Inspector content prepares asynchronously and reuses its cache")
func inspectorPreparationIsCached() async throws {
    let fixture = try AppTestJSONLFile(lineCount: 2)
    let viewModel = DocumentViewModel(
        document: BigJSONLDocument(url: fixture.url)
    )
    viewModel.openFile()
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
@Test("App search runs asynchronously and caps retained results")
func asynchronousSearchIsBounded() async throws {
    let fixture = try AppTestJSONLFile(lineCount: 1_000)
    let viewModel = DocumentViewModel(
        document: BigJSONLDocument(url: fixture.url)
    )
    viewModel.openFile()
    viewModel.performSearch(query: "match")
    #expect(viewModel.isSearching)

    for _ in 0..<200 where viewModel.isSearching {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(!viewModel.isSearching)
    #expect(viewModel.searchError == nil)
    #expect(viewModel.searchResults.count == 500)
}

private final class AppTestJSONLFile {
    let url: URL

    init(lineCount: Int) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bigjsonl-app-test-\(UUID().uuidString).jsonl")
        let contents = (1...lineCount)
            .map { "{\"line\":\($0),\"value\":\"match\"}" }
            .joined(separator: "\n")
        try Data(contents.utf8).write(to: url)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
