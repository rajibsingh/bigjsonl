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

    func run() throws {
        let url = URL(fileURLWithPath: file)
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw ValidationError("File not found or not readable: \(file)")
        }

        // TODO: Implement the viewer
        print("bigjsonl — viewing \(file)")
        print("  Line jump: \(line?.description ?? "none")")
        print("  Search pattern: \(search ?? "none")")
        print("  Color: \(noColor ? "disabled" : "enabled")")
    }
}
