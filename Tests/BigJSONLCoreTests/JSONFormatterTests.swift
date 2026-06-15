import Testing
import BigJSONLCore

@Test("Pretty printer adds structural line breaks and indentation")
func prettyPrintsJSON() {
    let input = "{\"outer\":[1,{\"key\":\"value\"}],\"empty\":{}}"
    let expected = """
        {
          "outer": [
            1,
            {
              "key": "value"
            }
          ],
          "empty": {}
        }
        """

    #expect(JSONFormatter.prettyPrinted(input) == expected)
}

@Test("Pretty printer preserves escaped string contents")
func prettyPrinterPreservesStrings() {
    let input = #"{"text":"commas, braces { } and escaped quote \" stay","line":"a\nb"}"#
    let formatted = JSONFormatter.prettyPrinted(input)

    #expect(formatted.contains(#""text": "commas, braces { } and escaped quote \" stay""#))
    #expect(formatted.contains(#""line": "a\nb""#))
    #expect(JSONTokenizer.tokenize(formatted).isValid)
}

@Test("Pretty printer leaves invalid JSON unchanged")
func invalidJSONIsUnchanged() {
    let input = "{\"broken\":"
    #expect(JSONFormatter.prettyPrinted(input) == input)
}

@Test("Display content prepares a large payload without revalidating formatted JSON")
func preparesLargeDisplayContent() {
    let payload = String(repeating: "x", count: 640_000)
    let input = #"{"event":"before_provider_request","payload":"\#(payload)"}"#
    let content = JSONFormatter.displayContent(input, isValid: true)

    #expect(content.text.contains("\n"))
    #expect(content.text.utf8.count > input.utf8.count)
    #expect(!content.tokens.isEmpty)
}
