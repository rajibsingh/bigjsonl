import Foundation
import Testing
import BigJSONLCore

@Test("No-match searches return an empty result")
func searchNoMatch() throws {
    let fixture = try TemporaryJSONLFile()

    let results = try Searcher.search(
        pattern: "definitely-not-present",
        in: fixture.url,
        tool: .grep
    )

    #expect(results.isEmpty)
}

@Test("Search limits output and accepts option-like patterns")
func searchLimitAndOptionPattern() throws {
    let fixture = try TemporaryJSONLFile(contents: """
        {"value":"-needle"}
        {"value":"-needle"}
        {"value":"-needle"}
        """)

    let results = try Searcher.search(
        pattern: "-needle",
        in: fixture.url,
        tool: .grep,
        limit: 2
    )

    #expect(results.count == 2)
    #expect(results.allSatisfy { $0.lineText.contains("-needle") })
}

@Test("Search results retain bounded snippets instead of full lines")
func searchResultsAreSnippetBounded() throws {
    let longValue = String(repeating: "x", count: 20_000)
    let fixture = try TemporaryJSONLFile(contents: """
        {"prefix":"\(longValue)","value":"needle","suffix":"\(longValue)"}
        """)

    let results = try Searcher.search(
        pattern: "needle",
        in: fixture.url,
        tool: .grep,
        limit: 1
    )

    let result = try #require(results.first)
    #expect(result.lineText.contains("needle"))
    #expect(result.lineText.count < 500)
}

@Test("Async search responds to task cancellation")
func searchCancellation() async throws {
    let contents = String(repeating: "{\"value\":\"haystack\"}\n", count: 100_000)
    let fixture = try TemporaryJSONLFile(contents: contents)
    let task = Task {
        try await Searcher.searchAsync(
            pattern: "not-present",
            in: fixture.url,
            tool: .grep
        )
    }

    task.cancel()

    await #expect(throws: CancellationError.self) {
        try await task.value
    }
}
