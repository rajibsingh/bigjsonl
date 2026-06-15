import SwiftUI
import UniformTypeIdentifiers
import BigJSONLCore

@main
struct BigJSONLApp: App {
    @State private var isFileImporterPresented = false
    @State private var documentURL: URL?

    var body: some Scene {
        WindowGroup {
            if let url = documentURL {
                ContentView(document: BigJSONLDocument(url: url))
            } else {
                welcomeView
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open JSONL File...") {
                    isFileImporterPresented = true
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
                isFileImporterPresented = true
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("o", modifiers: .command)
        }
        .frame(minWidth: 400, minHeight: 300)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.jsonl, .json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    documentURL = url
                }
            case .failure(let error):
                print("Failed to open file: \(error)")
            }
        }
    }
}
