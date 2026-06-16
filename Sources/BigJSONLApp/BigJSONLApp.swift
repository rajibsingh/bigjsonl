import SwiftUI
import BigJSONLCore
import AppKit

@main
struct BigJSONLApp: App {
    @State private var tabs: [TabItem] = []
    @State private var selectedTabID: UUID = UUID()
    @State private var searchQuery: String = ""

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    TabBarView(
                        tabs: tabs,
                        selectedID: selectedTabID,
                        onSelect: { selectedTabID = $0 },
                        onClose: closeTab,
                        onNew: newTab
                    )
                    searchToolbar
                    reloadButton
                }

                if let tab = selectedTab {
                    if let document = tab.document, let viewModel = tab.viewModel {
                        ContentView(
                            document: document,
                            viewModel: viewModel,
                            searchQuery: searchQuery,
                            onClearSearch: clearSearch
                        )
                        .id(tab.id)
                    } else {
                        welcomeView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(minWidth: 600, minHeight: 400)
            .onChange(of: selectedTabID) {
                if !searchQuery.isEmpty {
                    selectedTab?.viewModel?.performSearch(query: searchQuery)
                }
            }
            .onAppear {
                NSApplication.shared.setActivationPolicy(.regular)
                NSApplication.shared.activate()
                if tabs.isEmpty {
                    let first = TabItem()
                    tabs = [first]
                    selectedTabID = first.id
                }
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
            CommandGroup(after: .newItem) {
                Button("Reload File") {
                    reloadSelectedTab()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(selectedTab?.url == nil)
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
        let urls = FileOpenHandler.openFiles()
        guard !urls.isEmpty else { return }

        let unsupported = urls.filter { !FileOpenHandler.isSupportedFile($0) }
        if !unsupported.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Unsupported File Type"
            alert.informativeText = "Please select only .jsonl or .json files."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        for (index, url) in urls.enumerated() {
            _ = url.startAccessingSecurityScopedResource()
            if index == 0, let tab = selectedTab, tab.url == nil {
                // Reuse the current tab if it's empty
                tab.open(url: url)
            } else {
                let tab = TabItem(url: url)
                tabs.append(tab)
                if index == urls.count - 1 {
                    selectedTabID = tab.id
                }
            }
        }
    }

    // MARK: - Search

    private var searchToolbar: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField("Search pattern...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 150)
                .onSubmit {
                    selectedTab?.viewModel?.performSearch(query: searchQuery)
                }
            if selectedTab?.viewModel?.isSearching == true {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12)
            } else if !(selectedTab?.viewModel?.searchResults.isEmpty ?? true) || !searchQuery.isEmpty {
                Button {
                    clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func clearSearch() {
        searchQuery = ""
        selectedTab?.viewModel?.clearSearch()
    }

    // MARK: - Reload

    private var reloadButton: some View {
        Button {
            reloadSelectedTab()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12))
                .foregroundStyle(selectedTab?.url != nil ? .secondary : .tertiary)
        }
        .buttonStyle(.plain)
        .disabled(selectedTab?.url == nil)
        .help("Reload file (⌘R)")
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func reloadSelectedTab() {
        guard let tab = selectedTab, tab.url != nil else { return }
        clearSearch()
        tab.reload()
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
