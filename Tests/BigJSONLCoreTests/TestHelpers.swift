import Foundation

final class TemporaryJSONLFile {
    let url: URL

    init(contents: String = """
        {"line":1,"value":"alpha"}
        {"line":2,"value":"beta"}
        {"line":3,"value":"gamma"}
        {"line":4,"value":"delta"}
        {"line":5,"value":"epsilon"}
        """) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bigjsonl-test-\(UUID().uuidString).jsonl")
        try Data(contents.utf8).write(to: url)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
