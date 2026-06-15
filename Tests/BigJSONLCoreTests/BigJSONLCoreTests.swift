import Testing
import BigJSONLCore

@Test("Token type equality")
func tokenTypeEquality() {
    #expect(TokenType.punctuation == TokenType.punctuation)
    #expect(TokenType.key != TokenType.stringValue)
}

@Test("Token creation")
func tokenCreation() {
    let token = Token(range: 0..<5, type: .key)
    #expect(token.range == 0..<5)
    #expect(token.type == .key)
}

@Test("SearchResult creation")
func searchResultCreation() {
    let result = SearchResult(
        lineNumber: 42,
        byteOffset: 1024,
        lineText: "{\"key\": \"value\"}"
    )
    #expect(result.lineNumber == 42)
    #expect(result.byteOffset == 1024)
}

@Test("LineInfo creation")
func lineInfoCreation() {
    let info = LineInfo(
        lineNumber: 1,
        byteOffset: 0,
        byteLength: 24,
        isValidJSON: true,
        text: "{\"key\": \"value\"}",
        tokens: [Token(range: 0..<1, type: .punctuation)]
    )
    #expect(info.lineNumber == 1)
    #expect(info.isValidJSON)
    #expect(info.tokens.count == 1)
}
