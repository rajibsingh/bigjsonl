import AppKit
import UniformTypeIdentifiers

/// Opens an NSOpenPanel configured for JSONL files with hidden files visible.
enum FileOpenHandler {
    /// Presents an open-file dialog and returns the selected URL, or nil if cancelled.
    ///
    /// Unlike SwiftUI's `fileImporter`, this panel:
    /// - Shows hidden files (dotfiles) so users can browse `~/.pi/` directories
    /// - Accepts any file type (validation happens after selection)
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

        // Don't filter by content type — accept any file.
        // We validate the extension in openFile() instead.
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true

        let response = panel.runModal()
        return response == .OK ? panel.url : nil
    }

    /// Returns true if the file at the given URL is a supported type (.jsonl, .json).
    static func isSupportedFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "jsonl" || ext == "json"
    }
}
