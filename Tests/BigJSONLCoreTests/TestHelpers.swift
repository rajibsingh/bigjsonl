import Foundation

/// Returns the URL to the `test-files` directory at the package root.
///
/// Resolved by walking up from the current source file's path until we find
/// the `test-files` directory.
func testFilesDirectory() -> URL {
    // Start from this source file's directory
    var url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // BigJSONLCoreTests/
        .deletingLastPathComponent() // Tests/

    // Check if we're at the right level (should have Sources, Tests, test-files as siblings)
    let testFilesURL = url.appendingPathComponent("test-files")
    if FileManager.default.fileExists(atPath: testFilesURL.path) {
        return testFilesURL
    }

    // Fall back to a heuristic search up the tree
    var current = url
    while current.path != "/" {
        let candidate = current.appendingPathComponent("test-files")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        current.deleteLastPathComponent()
    }

    // Last resort: check the parent of the source dir
    url.deleteLastPathComponent()
    let parentTestFiles = url.appendingPathComponent("test-files")
    return parentTestFiles
}

/// Returns the URL of the first available test JSONL file.
func testJSONLFile() throws -> URL {
    let dir = testFilesDirectory()
    let contents = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
    guard let jsonl = contents.first(where: { $0.pathExtension == "jsonl" }) else {
        throw TestError.noTestFiles(dir)
    }
    return jsonl
}

enum TestError: Error, CustomStringConvertible {
    case noTestFiles(URL)

    var description: String {
        switch self {
        case .noTestFiles(let url):
            return "No .jsonl test files found in \(url.path)"
        }
    }
}
