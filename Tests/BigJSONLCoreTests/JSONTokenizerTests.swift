import Testing
import BigJSONLCore

@Test("Simple object tokenization")
func simpleObject() {
    let line = "{\"key\": \"value\"}"
    let (isValid, tokens) = JSONTokenizer.tokenize(line)

    #expect(isValid)
    #expect(tokens.count == 5)

    // { punctuation
    #expect(tokens[0].type == .punctuation)
    // "key" key
    #expect(tokens[1].type == .key)
    // : punctuation
    #expect(tokens[2].type == .punctuation)
    // "value" stringValue
    #expect(tokens[3].type == .stringValue)
    // } punctuation
    #expect(tokens[4].type == .punctuation)
}

@Test("Boolean and null tokenization")
func booleansAndNull() {
    let line = "{\"a\": true, \"b\": false, \"c\": null}"
    let (isValid, tokens) = JSONTokenizer.tokenize(line)

    #expect(isValid)
    let types = tokens.map(\.type)
    #expect(types.contains(.bool))
    #expect(types.contains(.null))
}

@Test("Number tokenization")
func numbers() {
    let line = "{\"int\": 42, \"float\": 3.14, \"sci\": 1e5}"
    let (isValid, tokens) = JSONTokenizer.tokenize(line)

    #expect(isValid)
    let types = tokens.map(\.type)
    #expect(types.filter { $0 == .number }.count == 3)
}

@Test("Array tokenization")
func array() {
    let line = "[1, 2, 3]"
    let (isValid, tokens) = JSONTokenizer.tokenize(line)

    #expect(isValid)
    #expect(tokens.count == 7) // [, 1, ,, 2, ,, 3, ]
    #expect(tokens[0].type == .punctuation) // [
    #expect(tokens[6].type == .punctuation) // ]
}

@Test("Invalid JSON returns invalid token")
func invalidJSON() {
    let line = "this is not json"
    let (isValid, tokens) = JSONTokenizer.tokenize(line)

    #expect(!isValid)
    #expect(tokens.count == 1)
    #expect(tokens[0].type == .invalid)
    #expect(tokens[0].range == 0..<UInt64(line.utf8.count))
}

@Test("Truncated JSON returns invalid token")
func truncatedJSON() {
    let line = "{\"key\": "
    let (isValid, tokens) = JSONTokenizer.tokenize(line)

    #expect(!isValid)
    #expect(tokens.count == 1)
    #expect(tokens[0].type == .invalid)
}

@Test("Token ranges are contiguous and cover the line")
func tokenRanges() {
    let line = "{\"a\":1}"
    let (isValid, tokens) = JSONTokenizer.tokenize(line)
    #expect(isValid)

    // Check that tokens cover the entire line without gaps
    var pos: UInt64 = 0
    for token in tokens {
        #expect(token.range.lowerBound == pos)
        pos = token.range.upperBound
    }
    #expect(pos == UInt64(line.utf8.count))
}

@Test("Real JSONL line from test data")
func realJSONLLine() {
    let line = "{\"timestamp\":\"2026-06-15T18:54:32.667Z\",\"event\":\"extension_load\",\"version\":\"0.1.0-skeleton\",\"detail\":\"full\"}"
    let (isValid, tokens) = JSONTokenizer.tokenize(line)

    #expect(isValid)
    #expect(tokens.count > 10)

    // Every key should be identified
    let keys = tokens.filter { $0.type == .key }
    #expect(keys.count == 4)
}
