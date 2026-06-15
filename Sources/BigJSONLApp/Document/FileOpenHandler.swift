import AppKit
import UniformTypeIdentifiers

/// Opens an NSOpenPanel configured for JSONL files with hidden files visible.
enum FileOpenHandler {
    /// Presents an open-file dialog and returns the selected URL, or nil if cancelled.
    ///
    /// Unlike SwiftUI's `fileImporter`, this panel:
    /// - Shows hidden files (dotfiles) so users can browse `~/.pi/` directories
    /// - Supports both `.jsonl` and `.json` extensions
    /// - Remembers the last-opened directory
    @MainActor
    static func openFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open JSONL File"
        panel.message = "Select a JSONL or JSON file to view"
        panel.prompt = "Open"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = false

        // Allow both .jsonl and .json
        panel.allowedContentTypes = [.jsonl, .json]

        // Also allow all files as a fallback (in case the UTType isn't registered)
        panel.allowsOtherFileTypes = true

        let response = panel.runModal()
        return response == .OK ? panel.url : nil
    }
}
