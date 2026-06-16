import ArgumentParser
import BigJSONLCore
import Foundation

@main
struct BigJSONL: AsyncParsableCommand {
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

    mutating func validate() throws {
        if let line, line == 0 {
            throw ValidationError("--line must be greater than zero.")
        }
        guard windowLines > 0 else {
            throw ValidationError("--window-lines must be greater than zero.")
        }
    }

    mutating func run() async throws {
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
                let results = try Searcher.search(
                    pattern: searchPattern,
                    in: url,
                    limit: 1
                )
                if let firstResult = results.first {
                    startLine = firstResult.lineNumber
                    print(ANSIRenderer.renderStatus("Found a match, jumping to line \(startLine)."))
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
        try await renderWindow(
            fromLine: startLine,
            count: UInt64(windowLines),
            mappedFile: mappedFile,
            index: &index
        )

        // Show footer
        let totalLines = index.lineCount
        let footerMessage: String
        if totalLines == 0 {
            footerMessage = "No lines | \(mappedFile.size.bytesFormatted)"
        } else {
            let requestedEnd = startLine.addingReportingOverflow(UInt64(windowLines) - 1)
            let shownEnd = requestedEnd.overflow
                ? totalLines
                : min(requestedEnd.partialValue, totalLines)
            let totalDescription = index.isComplete
                ? "of \(totalLines)"
                : "(more lines available)"
            footerMessage = "Showing lines \(startLine)-\(shownEnd) \(totalDescription) | \(mappedFile.size.bytesFormatted)"
        }
        let footer = ANSIRenderer.renderStatus(footerMessage)
        print(footer)
    }

    /// Renders a window of lines to stdout.
    private func renderWindow(
        fromLine start: UInt64,
        count: UInt64,
        mappedFile: MappedFile,
        index: inout LineOffsetIndex
    ) async throws {
        // Ensure the starting line is indexed
        let (targetLine, overflowed) = start.addingReportingOverflow(count)
        guard !overflowed else { return }
        index.ensureLineIndexed(targetLine, mappedFile: mappedFile)

        let maxLine = index.lineCount

        // Find the contiguous run of indexable lines in the window up front,
        // since the index may run out before `count` lines are reached.
        var lineNumbers: [UInt64] = []
        for lineNum in start..<min(start + count, maxLine + 1) {
            guard index.offsetForLine(lineNum) != nil,
                  index.byteRangeForLine(lineNum, fileSize: mappedFile.size) != nil else { break }
            lineNumbers.append(lineNum)
        }
        guard !lineNumbers.isEmpty else { return }

        // Reading bytes, decoding, and tokenizing each line is independent
        // and CPU-bound, so do it concurrently and print in line-number order
        // afterward.
        let snapshotIndex = index
        let noColor = noColor
        var rendered = [String?](repeating: nil, count: lineNumbers.count)
        try await withThrowingTaskGroup(of: (Int, String?).self) { group in
            for (i, lineNum) in lineNumbers.enumerated() {
                group.addTask {
                    guard let offset = snapshotIndex.offsetForLine(lineNum),
                          let range = snapshotIndex.byteRangeForLine(lineNum, fileSize: mappedFile.size) else {
                        return (i, nil)
                    }

                    let lineLength = range.upperBound - range.lowerBound
                    let lineText: String
                    if lineLength == 0 {
                        lineText = ""
                    } else {
                        let decoded = mappedFile.withUnsafeBytes(offset: offset, length: lineLength) {
                            String(bytes: $0, encoding: .utf8)
                        } ?? nil
                        if let str = decoded {
                            lineText = str.trimmingCharacters(in: ["\n", "\r"])
                        } else {
                            lineText = "<invalid UTF-8>"
                        }
                    }

                    let (_, tokens) = JSONTokenizer.tokenize(lineText)

                    let rendered = ANSIRenderer.renderLine(
                        lineText: lineText,
                        tokens: tokens,
                        lineNumber: lineNum,
                        noColor: noColor
                    )
                    return (i, rendered)
                }
            }
            for try await (i, line) in group {
                rendered[i] = line
            }
        }

        for line in rendered {
            if let line {
                print(line)
            }
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
