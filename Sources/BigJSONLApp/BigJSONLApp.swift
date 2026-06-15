import SwiftUI
import BigJSONLCore

@main
struct BigJSONLApp: App {
    @State private var documentURL: URL? {
        didSet {
            // Release security scope for the previous file
            if let old = oldValue {
                old.stopAccessingSecurityScopedResource()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if let url = documentURL {
                ContentView(document: BigJSONLDocument(url: url))
                    .onDisappear {
                        // Release security scope when window closes
                        url.stopAccessingSecurityScopedResource()
                    }
            } else {
                welcomeView
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open JSONL File...") {
                    openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("bigjsonl")
                .font(.largeTitle)
                .fontWeight(.light)

            Text("View large JSONL files, one line at a time.")
                .foregroundStyle(.secondary)

            Button("Open File...") {
                openFile()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("o", modifiers: .command)
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private func openFile() {
        guard let url = FileOpenHandler.openFile() else { return }

        // Validate file extension
        guard FileOpenHandler.isSupportedFile(url) else {
            let alert = NSAlert()
            alert.messageText = "Unsupported File Type"
            alert.informativeText = "Please select a .jsonl or .json file."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // Start accessing security-scoped resource
        _ = url.startAccessingSecurityScopedResource()
        documentURL = url
    }
}
