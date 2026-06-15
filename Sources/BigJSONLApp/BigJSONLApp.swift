import SwiftUI
import BigJSONLCore
import AppKit

@main
struct BigJSONLApp: App {
    @State private var tabs: [TabItem] = [TabItem()]
    @State private var selectedTabID: UUID = UUID()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                TabBarView(
                    tabs: tabs,
                    selectedID: selectedTabID,
                    onSelect: { selectedTabID = $0 },
                    onClose: closeTab,
                    onNew: newTab
                )

                if let tab = selectedTab {
                    if let document = tab.document {
                        ContentView(document: document)
                            .id(tab.id)
                    } else {
                        welcomeView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(minWidth: 600, minHeight: 400)
            .onAppear {
                selectedTabID = tabs[0].id
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    newTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Open JSONL File...") {
                    openFileInSelectedTab()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }

    // MARK: - Selected tab

    private var selectedTab: TabItem? {
        tabs.first { $0.id == selectedTabID }
    }

    // MARK: - Tab management

    private func newTab() {
        let tab = TabItem()
        tabs.append(tab)
        selectedTabID = tab.id
    }

    private func closeTab(id: UUID) {
        guard tabs.count > 1 else {
            // Only one tab left — reset it to empty rather than closing
            if let only = tabs.first {
                only.url?.stopAccessingSecurityScopedResource()
                only.url = nil
                only.document = nil
            }
            return
        }

        if let idx = tabs.firstIndex(where: { $0.id == id }) {
            tabs.remove(at: idx)
            let newIdx = max(0, idx - 1)
            selectedTabID = tabs[newIdx].id
        }
    }

    private func openFileInSelectedTab() {
        guard let url = FileOpenHandler.openFile() else { return }

        guard FileOpenHandler.isSupportedFile(url) else {
            let alert = NSAlert()
            alert.messageText = "Unsupported File Type"
            alert.informativeText = "Please select a .jsonl or .json file."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        _ = url.startAccessingSecurityScopedResource()

        if let tab = selectedTab {
            tab.open(url: url)
        }
    }

    // MARK: - Welcome screen

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
                openFileInSelectedTab()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("o", modifiers: .command)
        }
    }
}
