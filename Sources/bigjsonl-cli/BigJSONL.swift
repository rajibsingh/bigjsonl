import ArgumentParser
import BigJSONLCore
import Foundation

@main
struct BigJSONL: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bigjsonl",
        abstract: "View large JSONL files, one line at a time.",
        discussion: """
        Opens a JSONL file and displays each line as a syntax-highlighted document.
        Supports searching via grep/ripgrep and jumping to specific lines.
        """
    )

    @Argument(
        help: "Path to the JSONL file to view.",
        completion: .file(extensions: ["jsonl", "json"])
    )
    var file: String

    @Option(
        name: [.short, .long],
        help: "Jump to a specific line number on open."
    )
    var line: UInt64?

    @Option(
        name: [.short, .long],
        help: "Search for a pattern in the file and jump to the first match."
    )
    var search: String?

    @Flag(
        name: [.long],
        help: "Disable ANSI color output."
    )
    var noColor: Bool = false

    @Option(
        name: .long,
        help: "Number of lines to display (viewport height)."
    )
    var windowLines: Int = 20

    mutating func run() throws {
        let url = URL(fileURLWithPath: file)
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw ValidationError("File not found or not readable: \(file)")
        }

        let mappedFile = try MappedFile(url: url)
        var index = LineOffsetIndex()

        // Determine the starting line
        var startLine: UInt64 = 1

        if let searchPattern = search {
            // Run search and jump to first match
            print(ANSIRenderer.renderStatus("Searching for \"\(searchPattern)\"..."))
            do {
                let results = try Searcher.search(pattern: searchPattern, in: url)
                if let firstResult = results.first {
                    startLine = firstResult.lineNumber
                    print(ANSIRenderer.renderStatus("Found \(results.count) match(es), jumping to line \(startLine)."))
                } else {
                    print(ANSIRenderer.renderStatus("No matches found."))
                    return
                }
            } catch let error as SearchError {
                print(ANSIRenderer.renderError("Search failed: \(error.description)"))
                return
            }
        }

        if let jumpLine = line {
            startLine = jumpLine
        }

        // Render the viewport
        renderWindow(
            fromLine: startLine,
            count: UInt64(windowLines),
            mappedFile: mappedFile,
            index: &index
        )

        // Show footer
        let totalLines = index.lineCount
        let footer = ANSIRenderer.renderStatus(
            "Showing lines \(startLine)-\(min(startLine + UInt64(windowLines) - 1, totalLines)) of \(totalLines) | \(mappedFile.size.bytesFormatted)"
        )
        print(footer)
    }

    /// Renders a window of lines to stdout.
    private func renderWindow(
        fromLine start: UInt64,
        count: UInt64,
        mappedFile: MappedFile,
        index: inout LineOffsetIndex
    ) {
        // Ensure the starting line is indexed
        let targetLine = start + count
        index.ensureLineIndexed(targetLine, mappedFile: mappedFile)

        let maxLine = index.lineCount

        for lineNum in start..<min(start + count, maxLine + 1) {
            guard let offset = index.offsetForLine(lineNum) else { break }
            guard let range = index.byteRangeForLine(lineNum, fileSize: mappedFile.size) else {
                break
            }

            // Read the raw bytes for this line
            let lineLength = range.upperBound - range.lowerBound
            let data = mappedFile.read(offset: offset, length: lineLength)

            // Convert DispatchData to String
            let lineText: String
            if data.isEmpty {
                lineText = ""
            } else {
                let rawData = Data(data)
                if let str = String(data: rawData, encoding: .utf8) {
                    // Trim trailing newline/carriage return for display
                    lineText = str.trimmingCharacters(in: ["\n", "\r"])
                } else {
                    lineText = "<invalid UTF-8>"
                }
            }

            // Tokenize
            let (isValid, tokens) = JSONTokenizer.tokenize(lineText)

            // Render
            let rendered = ANSIRenderer.renderLine(
                lineText: lineText,
                tokens: isValid ? tokens : tokens,
                lineNumber: lineNum,
                noColor: noColor
            )
            print(rendered)
        }
    }
}

// MARK: - Formatting helpers

extension UInt64 {
    var bytesFormatted: String {
        if self < 1024 {
            return "\(self) B"
        } else if self < 1024 * 1024 {
            return String(format: "%.1f KB", Double(self) / 1024)
        } else if self < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", Double(self) / (1024 * 1024))
        } else {
            return String(format: "%.1f GB", Double(self) / (1024 * 1024 * 1024))
        }
    }
}
