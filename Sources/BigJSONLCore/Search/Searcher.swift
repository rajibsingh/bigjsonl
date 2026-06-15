import Foundation

/// A subprocess-based search utility that wraps grep/ripgrep.
///
/// Auto-detects `rg` (ripgrep) on `$PATH` for faster, byte-offset-aware
/// searching, and falls back to `grep` if ripgrep is not available.
public enum Searcher {

    /// The search tool to use.
    public enum Tool: String, CustomStringConvertible, Sendable {
        case rg
        case grep

        public var description: String { rawValue }
    }

    /// Detects the best available search tool.
    /// - Returns: `.rg` if ripgrep is on `$PATH`, otherwise `.grep`.
    public static var preferredTool: Tool {
        if which("rg") != nil {
            return .rg
        }
        return .grep
    }

    /// Searches a file for lines matching the given pattern.
    ///
    /// - Parameters:
    ///   - pattern: The search pattern (passed directly to grep/rg as-is).
    ///   - fileURL: The URL of the file to search.
    ///   - tool: The search tool to use. Defaults to `preferredTool`.
    /// - Returns: An array of `SearchResult` sorted by line number.
    /// - Throws: `SearchError` if the subprocess fails or output can't be parsed.
    public static func search(
        pattern: String,
        in fileURL: URL,
        tool: Tool = preferredTool,
        limit: Int = 500
    ) throws -> [SearchResult] {
        guard limit > 0 else {
            throw SearchError.invalidLimit(limit)
        }
        return try search(
            pattern: pattern,
            in: fileURL,
            tool: tool,
            limit: limit,
            controller: nil
        )
    }

    /// Searches without blocking the caller's actor and cancels the subprocess
    /// when the surrounding task is cancelled.
    public static func searchAsync(
        pattern: String,
        in fileURL: URL,
        tool: Tool = preferredTool,
        limit: Int = 500
    ) async throws -> [SearchResult] {
        guard limit > 0 else {
            throw SearchError.invalidLimit(limit)
        }
        let controller = ProcessController()

        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                return try search(
                    pattern: pattern,
                    in: fileURL,
                    tool: tool,
                    limit: limit,
                    controller: controller
                )
            }.value
        } onCancel: {
            controller.cancel()
        }
    }

    private static func search(
        pattern: String,
        in fileURL: URL,
        tool: Tool,
        limit: Int,
        controller: ProcessController?
    ) throws -> [SearchResult] {
        let toolPath = try resolveToolPath(tool)
        let args = buildArgs(for: tool, pattern: pattern, fileURL: fileURL, limit: limit)
        let output = try runSubprocess(tool: toolPath, args: args, controller: controller)
        return try parseResults(output: output, tool: tool)
    }

    // MARK: - Private

    /// Build the argument list for the given tool.
    private static func buildArgs(
        for tool: Tool,
        pattern: String,
        fileURL: URL,
        limit: Int
    ) -> [String] {
        switch tool {
        case .rg:
            return [
                "--byte-offset",
                "--line-number",
                "--no-heading",
                "--max-count",
                String(limit),
                "--",
                pattern,
                fileURL.path
            ]
        case .grep:
            return [
                "--byte-offset",
                "--line-number",
                "--max-count=\(limit)",
                "--",
                pattern,
                fileURL.path
            ]
        }
    }

    /// Parse grep/rg output lines into `SearchResult` values.
    ///
    /// Format (both): `lineNumber:byteOffset:lineText`
    private static func parseResults(output: String, tool: Tool) throws -> [SearchResult] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        var results: [SearchResult] = []
        results.reserveCapacity(lines.count)

        for line in lines {
            guard let firstColon = line.firstIndex(of: ":") else { continue }
            let lineNumberStr = line[line.startIndex..<firstColon]
            guard let lineNumber = UInt64(lineNumberStr) else { continue }

            let afterFirst = line.index(after: firstColon)
            guard let secondColon = line[afterFirst...].firstIndex(of: ":") else { continue }
            let byteOffsetStr = line[afterFirst..<secondColon]
            guard let byteOffset = UInt64(byteOffsetStr) else { continue }

            let afterSecond = line.index(after: secondColon)
            let lineText = String(line[afterSecond...])

            results.append(SearchResult(
                lineNumber: lineNumber,
                byteOffset: byteOffset,
                lineText: lineText
            ))
        }

        return results
    }

    /// Run a subprocess, read stdout, return it as a string.
    ///
    /// Reads stdout on a background queue while the process runs to avoid
    /// pipe buffer deadlocks (pipe buffer is ~64KB on macOS).
    private static func runSubprocess(
        tool: String,
        args: [String],
        controller: ProcessController?
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Collect stdout on a background queue to avoid pipe deadlock
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        let stdoutData = LockedData()
        let stderrData = LockedData()

        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            stdoutData.set(stdoutHandle.readDataToEndOfFile())
            group.leave()
        }

        group.enter()
        DispatchQueue.global().async {
            stderrData.set(stderrHandle.readDataToEndOfFile())
            group.leave()
        }

        try process.run()
        controller?.setProcess(process)
        process.waitUntilExit()

        // Wait for both reads to complete
        group.wait()

        if controller?.isCancelled == true {
            throw CancellationError()
        }

        // grep and ripgrep use status 1 for a successful search with no matches.
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            let stderr = String(data: stderrData.value, encoding: .utf8) ?? ""
            throw SearchError.searchFailed(
                tool: tool,
                exitCode: process.terminationStatus,
                stderr: stderr
            )
        }

        return String(data: stdoutData.value, encoding: .utf8) ?? ""
    }

    /// Check if a command is available on `$PATH`.
    private static func which(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Find the full path of a tool.
    private static func resolveToolPath(_ tool: Tool) throws -> String {
        guard let path = which(tool.rawValue) else {
            throw SearchError.toolNotFound(tool)
        }
        return path
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var value: Data {
        lock.withLock { data }
    }

    func set(_ data: Data) {
        lock.withLock {
            self.data = data
        }
    }
}

private final class ProcessController: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func setProcess(_ process: Process) {
        lock.withLock {
            self.process = process
            if cancelled, process.isRunning {
                process.terminate()
            }
        }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            if let process, process.isRunning {
                process.terminate()
            }
        }
    }
}

// MARK: - Errors

public enum SearchError: Error, CustomStringConvertible {
    case toolNotFound(Searcher.Tool)
    case searchFailed(tool: String, exitCode: Int32, stderr: String)
    case invalidLimit(Int)

    public var description: String {
        switch self {
        case .toolNotFound(let tool):
            return "\(tool) not found on $PATH"
        case .searchFailed(let tool, let exitCode, let stderr):
            return "\(tool) exited with code \(exitCode): \(stderr)"
        case .invalidLimit(let limit):
            return "Search result limit must be positive, got \(limit)"
        }
    }
}
